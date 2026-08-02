import Foundation

public struct AgentSessionKey: Hashable, Sendable {
    public let kind: AgentKind
    public let sessionID: String

    public init(kind: AgentKind, sessionID: String) {
        self.kind = kind
        self.sessionID = sessionID
    }
}

public struct AgentHookSnapshot: Sendable {
    public let activeAgents: [RunningAgent]
    public let authoritativeSessions: Set<AgentSessionKey>

    public init(
        activeAgents: [RunningAgent],
        authoritativeSessions: Set<AgentSessionKey>
    ) {
        self.activeAgents = activeAgents
        self.authoritativeSessions = authoritativeSessions
    }
}

public enum AgentHookEventAction: Equatable, Sendable {
    case activate
    case heartbeat
    case deactivate
    case deactivateSession
    case ignore
}

public struct AgentHookEvent: Decodable, Sendable {
    public let sessionID: String
    public let turnID: String?
    public let promptID: String?
    public let hookEventName: String

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case turnID = "turn_id"
        case promptID = "prompt_id"
        case hookEventName = "hook_event_name"
    }

    public var activityID: String? {
        turnID ?? promptID
    }

    public var action: AgentHookEventAction {
        switch hookEventName {
        case "UserPromptSubmit":
            return .activate
        case "PreToolUse",
             "PermissionRequest",
             "PostToolUse",
             "PostToolUseFailure",
             "PostToolBatch",
             "SubagentStart",
             "SubagentStop":
            return .heartbeat
        case "Stop", "StopFailure":
            return .deactivate
        case "SessionEnd":
            return .deactivateSession
        default:
            return .ignore
        }
    }
}

public enum AgentActivityStoreError: LocalizedError {
    case invalidEvent

    public var errorDescription: String? {
        "Agent 活动事件缺少必要字段或字段不安全。"
    }
}

public final class AgentHookActivityStore: @unchecked Sendable {
    private enum LeaseState: String, Codable {
        case active
        case inactive
    }

    private struct LeaseRecord: Codable {
        let schemaVersion: Int
        let kind: AgentKind
        let sessionID: String
        let activityID: String
        var state: LeaseState
        let source: AgentStatusSource
        var lastEventName: String
        var updatedAt: Date

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case kind
            case providerID
            case displayName
            case sessionID
            case activityID
            case state
            case source
            case lastEventName
            case updatedAt
        }

        init(
            schemaVersion: Int,
            kind: AgentKind,
            sessionID: String,
            activityID: String,
            state: LeaseState,
            source: AgentStatusSource,
            lastEventName: String,
            updatedAt: Date
        ) {
            self.schemaVersion = schemaVersion
            self.kind = kind
            self.sessionID = sessionID
            self.activityID = activityID
            self.state = state
            self.source = source
            self.lastEventName = lastEventName
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(
                Int.self,
                forKey: .schemaVersion
            ) ?? 1

            if let providerID = try container.decodeIfPresent(
                String.self,
                forKey: .providerID
            ) {
                let displayName = try container.decodeIfPresent(
                    String.self,
                    forKey: .displayName
                )
                guard let provider = AgentKind(
                    identifier: providerID,
                    displayName: displayName
                ) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .providerID,
                        in: container,
                        debugDescription: "Invalid provider identity."
                    )
                }
                kind = provider
            } else {
                kind = try container.decode(AgentKind.self, forKey: .kind)
            }

            sessionID = try container.decode(String.self, forKey: .sessionID)
            activityID = try container.decode(
                String.self,
                forKey: .activityID
            )
            state = try container.decode(LeaseState.self, forKey: .state)
            source = try container.decodeIfPresent(
                AgentStatusSource.self,
                forKey: .source
            ) ?? .preciseHook
            lastEventName = try container.decode(
                String.self,
                forKey: .lastEventName
            )
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(2, forKey: .schemaVersion)
            try container.encode(kind.identifier, forKey: .providerID)
            try container.encode(kind.displayName, forKey: .displayName)
            try container.encode(sessionID, forKey: .sessionID)
            try container.encode(activityID, forKey: .activityID)
            try container.encode(state, forKey: .state)
            try container.encode(source, forKey: .source)
            try container.encode(lastEventName, forKey: .lastEventName)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }

    public let rootDirectory: URL
    public let activeLeaseTimeout: TimeInterval
    public let inactiveAuthorityWindow: TimeInterval
    public let maximumLeaseRecords: Int

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let lock = NSLock()

    public init(
        rootDirectory: URL = AgentHookActivityStore.defaultRootDirectory(),
        activeLeaseTimeout: TimeInterval = 1_800,
        inactiveAuthorityWindow: TimeInterval = 86_400,
        maximumLeaseRecords: Int = 128,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.activeLeaseTimeout = activeLeaseTimeout
        self.inactiveAuthorityWindow = inactiveAuthorityWindow
        self.maximumLeaseRecords = min(max(1, maximumLeaseRecords), 1_024)
        self.fileManager = fileManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public static func defaultRootDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("AgentAwake", isDirectory: true)
            .appendingPathComponent("AgentActivity", isDirectory: true)
    }

    public func prepareDirectory() throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureRootDirectory()
    }

    @discardableResult
    public func handle(
        provider: AgentKind,
        input: Data,
        now: Date = Date()
    ) throws -> AgentHookEventAction {
        let hookEvent = try decoder.decode(AgentHookEvent.self, from: input)
        let action = hookEvent.action
        guard action != .ignore else {
            return action
        }

        let kind: AgentActivityEventKind
        switch action {
        case .activate:
            kind = .start
        case .heartbeat:
            kind = .heartbeat
        case .deactivate, .deactivateSession:
            kind = .stop
        case .ignore:
            return .ignore
        }

        guard let event = AgentActivityEvent(
            provider: provider,
            sessionID: hookEvent.sessionID,
            activityID: hookEvent.activityID,
            kind: kind,
            source: .preciseHook,
            eventName: hookEvent.hookEventName
        ) else {
            throw AgentActivityStoreError.invalidEvent
        }
        return try handleResolved(event, action: action, now: now)
    }

    @discardableResult
    public func handle(
        event: AgentActivityEvent,
        now: Date = Date()
    ) throws -> AgentHookEventAction {
        let action: AgentHookEventAction
        switch event.kind {
        case .start:
            action = .activate
        case .heartbeat:
            action = .heartbeat
        case .stop:
            action = .deactivate
        }
        return try handleResolved(event, action: action, now: now)
    }

    public func snapshot(now: Date = Date()) -> AgentHookSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let records = recentRecords(now: now)
        var activeAgents: [RunningAgent] = []
        var authoritativeSessions: Set<AgentSessionKey> = []

        for item in records {
            let record = item.record
            let age = max(0, now.timeIntervalSince(record.updatedAt))
            let key = AgentSessionKey(
                kind: record.kind,
                sessionID: record.sessionID
            )

            switch record.state {
            case .active where age <= activeLeaseTimeout:
                authoritativeSessions.insert(key)
                activeAgents.append(
                    RunningAgent(
                        kind: record.kind,
                        sessionID: record.sessionID,
                        activityLogPath: item.url.path,
                        source: record.source
                    )
                )
            case .inactive where age <= inactiveAuthorityWindow:
                authoritativeSessions.insert(key)
            default:
                continue
            }
        }

        return AgentHookSnapshot(
            activeAgents: activeAgents.sorted(by: Self.agentSort),
            authoritativeSessions: authoritativeSessions
        )
    }

    private func handleResolved(
        _ event: AgentActivityEvent,
        action: AgentHookEventAction,
        now: Date
    ) throws -> AgentHookEventAction {
        lock.lock()
        defer { lock.unlock() }
        try ensureRootDirectory()

        switch action {
        case .activate:
            try deactivateOtherActivities(
                provider: event.provider,
                sessionID: event.sessionID,
                keeping: event.activityID,
                eventName: event.eventName,
                now: now
            )
            try upsertActiveLease(event: event, now: now)
        case .heartbeat:
            try upsertActiveLease(event: event, now: now)
        case .deactivate:
            try deactivate(event: event, now: now)
        case .deactivateSession:
            try deactivateSession(
                provider: event.provider,
                sessionID: event.sessionID,
                eventName: event.eventName,
                source: event.source,
                now: now
            )
        case .ignore:
            break
        }

        return action
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }

    private func upsertActiveLease(
        event: AgentActivityEvent,
        now: Date
    ) throws {
        let activityID = event.activityID ?? event.sessionID
        let record = LeaseRecord(
            schemaVersion: 2,
            kind: event.provider,
            sessionID: event.sessionID,
            activityID: activityID,
            state: .active,
            source: event.source,
            lastEventName: event.eventName,
            updatedAt: now
        )
        try write(record)
    }

    private func deactivate(
        event: AgentActivityEvent,
        now: Date
    ) throws {
        if let activityID = event.activityID {
            let url = recordURL(
                provider: event.provider,
                sessionID: event.sessionID
            )
            if var record = readRecord(at: url) {
                guard record.activityID == activityID else {
                    return
                }
                record.state = .inactive
                record.lastEventName = event.eventName
                record.updatedAt = now
                try write(record)
                return
            }
        }

        try deactivateSession(
            provider: event.provider,
            sessionID: event.sessionID,
            eventName: event.eventName,
            source: event.source,
            now: now
        )
    }

    private func deactivateSession(
        provider: AgentKind,
        sessionID: String,
        eventName: String,
        source: AgentStatusSource,
        now: Date
    ) throws {
        var foundRecord = false
        for url in recordURLs() {
            guard var record = readRecord(at: url),
                  record.kind == provider,
                  record.sessionID == sessionID
            else {
                continue
            }
            foundRecord = true
            record.state = .inactive
            record.lastEventName = eventName
            record.updatedAt = now
            try write(record)
        }

        if !foundRecord {
            try write(
                LeaseRecord(
                    schemaVersion: 2,
                    kind: provider,
                    sessionID: sessionID,
                    activityID: sessionID,
                    state: .inactive,
                    source: source,
                    lastEventName: eventName,
                    updatedAt: now
                )
            )
        }
    }

    private func deactivateOtherActivities(
        provider: AgentKind,
        sessionID: String,
        keeping activityID: String?,
        eventName: String,
        now: Date
    ) throws {
        for url in recordURLs() {
            guard var record = readRecord(at: url),
                  record.kind == provider,
                  record.sessionID == sessionID,
                  record.state == .active,
                  record.activityID != activityID
            else {
                continue
            }
            record.state = .inactive
            record.lastEventName = eventName
            record.updatedAt = now
            try write(record)
        }
    }

    private func recentRecords(
        now: Date
    ) -> [(url: URL, record: LeaseRecord)] {
        var records: [(url: URL, record: LeaseRecord)] = []
        let expirationWindow = max(
            activeLeaseTimeout,
            inactiveAuthorityWindow
        )

        for url in recordURLs() {
            guard let record = readRecord(at: url) else {
                continue
            }
            if record.updatedAt.timeIntervalSince(now) > 300 {
                // A corrupted or clock-skewed lease must not keep the Mac
                // awake indefinitely.
                try? fileManager.removeItem(at: url)
                continue
            }
            if now.timeIntervalSince(record.updatedAt) > expirationWindow {
                try? fileManager.removeItem(at: url)
                continue
            }
            records.append((url, record))
        }

        records.sort {
            if $0.record.state != $1.record.state {
                return $0.record.state == .active
            }
            return $0.record.updatedAt > $1.record.updatedAt
        }
        if records.count > maximumLeaseRecords {
            for item in records.dropFirst(maximumLeaseRecords) {
                try? fileManager.removeItem(at: item.url)
            }
            records = Array(records.prefix(maximumLeaseRecords))
        }
        return records
    }

    private func recordURLs() -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        let inspectionLimit = min(
            max(maximumLeaseRecords * 4, 128),
            1_024
        )
        var urls: [URL] = []
        urls.reserveCapacity(min(inspectionLimit, maximumLeaseRecords))
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "json" else {
                continue
            }
            urls.append(url)
            if urls.count >= inspectionLimit {
                break
            }
        }
        return urls
    }

    private func readRecord(at url: URL) -> LeaseRecord? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize <= 16_384
        else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(LeaseRecord.self, from: data)
    }

    private func write(_ record: LeaseRecord) throws {
        let data = try encoder.encode(record)
        let url = recordURL(
            provider: record.kind,
            sessionID: record.sessionID
        )
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func recordURL(
        provider: AgentKind,
        sessionID: String
    ) -> URL {
        let name = [
            provider.identifier,
            Self.stableHash(sessionID)
        ].joined(separator: "-")
        return rootDirectory
            .appendingPathComponent(name)
            .appendingPathExtension("json")
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func agentSort(
        _ lhs: RunningAgent,
        _ rhs: RunningAgent
    ) -> Bool {
        if lhs.kind.displayName == rhs.kind.displayName {
            return lhs.sessionID < rhs.sessionID
        }
        return lhs.kind.displayName < rhs.kind.displayName
    }
}
