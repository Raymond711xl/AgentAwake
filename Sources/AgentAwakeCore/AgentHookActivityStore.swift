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
        var lastEventName: String
        var updatedAt: Date
    }

    public let rootDirectory: URL
    public let activeLeaseTimeout: TimeInterval
    public let inactiveAuthorityWindow: TimeInterval

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let lock = NSLock()

    public init(
        rootDirectory: URL = AgentHookActivityStore.defaultRootDirectory(),
        activeLeaseTimeout: TimeInterval = 1_800,
        inactiveAuthorityWindow: TimeInterval = 86_400,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.activeLeaseTimeout = activeLeaseTimeout
        self.inactiveAuthorityWindow = inactiveAuthorityWindow
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

    @discardableResult
    public func handle(
        provider: AgentKind,
        input: Data,
        now: Date = Date()
    ) throws -> AgentHookEventAction {
        let event = try decoder.decode(AgentHookEvent.self, from: input)
        let action = event.action

        guard action != .ignore else {
            return action
        }

        lock.lock()
        defer { lock.unlock() }

        try ensureRootDirectory()

        switch action {
        case .activate:
            try deactivateOtherActivities(
                provider: provider,
                sessionID: event.sessionID,
                keeping: event.activityID,
                eventName: event.hookEventName,
                now: now
            )
            try upsertActiveLease(
                provider: provider,
                event: event,
                now: now
            )

        case .heartbeat:
            try upsertActiveLease(
                provider: provider,
                event: event,
                now: now
            )

        case .deactivate:
            try deactivate(
                provider: provider,
                event: event,
                now: now
            )

        case .deactivateSession:
            try deactivateSession(
                provider: provider,
                sessionID: event.sessionID,
                eventName: event.hookEventName,
                now: now
            )

        case .ignore:
            break
        }

        return action
    }

    public func snapshot(now: Date = Date()) -> AgentHookSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return AgentHookSnapshot(
                activeAgents: [],
                authoritativeSessions: []
            )
        }

        var activeAgents: [RunningAgent] = []
        var authoritativeSessions: Set<AgentSessionKey> = []

        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(
                      LeaseRecord.self,
                      from: data
                  )
            else {
                continue
            }

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
                        activityLogPath: url.path,
                        source: .lifecycleHook
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
        provider: AgentKind,
        event: AgentHookEvent,
        now: Date
    ) throws {
        let activityID = event.activityID ?? event.sessionID
        let record = LeaseRecord(
            schemaVersion: 1,
            kind: provider,
            sessionID: event.sessionID,
            activityID: activityID,
            state: .active,
            lastEventName: event.hookEventName,
            updatedAt: now
        )
        try write(record)
    }

    private func deactivate(
        provider: AgentKind,
        event: AgentHookEvent,
        now: Date
    ) throws {
        if let activityID = event.activityID {
            let url = recordURL(
                provider: provider,
                sessionID: event.sessionID
            )

            if var record = readRecord(at: url) {
                guard record.activityID == activityID else {
                    return
                }

                record.state = .inactive
                record.lastEventName = event.hookEventName
                record.updatedAt = now
                try write(record)
                return
            }
        }

        try deactivateSession(
            provider: provider,
            sessionID: event.sessionID,
            eventName: event.hookEventName,
            now: now
        )
    }

    private func deactivateSession(
        provider: AgentKind,
        sessionID: String,
        eventName: String,
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
            let record = LeaseRecord(
                schemaVersion: 1,
                kind: provider,
                sessionID: sessionID,
                activityID: sessionID,
                state: .inactive,
                lastEventName: eventName,
                updatedAt: now
            )
            try write(record)
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

    private func recordURLs() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    private func readRecord(at url: URL) -> LeaseRecord? {
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
        if lhs.kind.rawValue == rhs.kind.rawValue {
            return lhs.sessionID < rhs.sessionID
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}
