import Foundation

public protocol AgentDetecting: Sendable {
    func runningAgents() -> [RunningAgent]
}

public enum AgentActivityLogFormat: Sendable {
    case codex
    case claude
}

public enum AgentActivityLineParser {
    public static func updatedState(
        currentState: Bool,
        line: Data,
        format: AgentActivityLogFormat
    ) -> Bool {
        guard let envelope = try? JSONDecoder().decode(
            ActivityEnvelope.self,
            from: line
        ) else {
            return currentState
        }

        switch format {
        case .codex:
            guard envelope.type == "event_msg" else {
                return currentState
            }

            switch envelope.payload?.type {
            case "task_started":
                return true
            case "task_complete":
                return false
            default:
                return currentState
            }

        case .claude:
            if envelope.type == "user" {
                return true
            }

            if envelope.type == "assistant",
               envelope.message?.stopReason == "end_turn"
            {
                return false
            }

            return currentState
        }
    }
}

public final class SystemAgentDetector: AgentDetecting, @unchecked Sendable {
    private struct LogRoot {
        let url: URL
        let kind: AgentKind
        let format: AgentActivityLogFormat
    }

    private struct FileState {
        let kind: AgentKind
        let format: AgentActivityLogFormat
        let sessionID: String
        var offset: UInt64 = 0
        var partialLine = Data()
        var isActive = false
        var modificationDate = Date.distantPast
    }

    private let fileManager: FileManager
    private let logRoots: [LogRoot]
    private let recentFileWindow: TimeInterval
    private let activeSilenceTimeout: TimeInterval
    private let hookActivityStore: AgentHookActivityStore
    private let lock = NSLock()
    private var fileStates: [URL: FileState] = [:]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        hookActivityDirectory: URL? = nil,
        recentFileWindow: TimeInterval = 86_400,
        activeSilenceTimeout: TimeInterval = 1_800,
        hookLeaseTimeout: TimeInterval = 1_800
    ) {
        let codexRoot = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let claudeRoot = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)

        self.fileManager = .default
        self.logRoots = [
            LogRoot(url: codexRoot, kind: .codex, format: .codex),
            LogRoot(url: claudeRoot, kind: .claude, format: .claude)
        ]
        self.recentFileWindow = recentFileWindow
        self.activeSilenceTimeout = activeSilenceTimeout
        self.hookActivityStore = AgentHookActivityStore(
            rootDirectory: hookActivityDirectory
                ?? AgentHookActivityStore.defaultRootDirectory(
                    homeDirectory: homeDirectory
                ),
            activeLeaseTimeout: hookLeaseTimeout
        )
    }

    public func runningAgents() -> [RunningAgent] {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let hookSnapshot = hookActivityStore.snapshot(now: now)
        let candidates = candidateLogs(now: now)
        let candidateURLs = Set(candidates.map(\.url))

        for candidate in candidates {
            updateState(for: candidate)
        }

        fileStates = fileStates.filter { url, state in
            candidateURLs.contains(url)
                || now.timeIntervalSince(state.modificationDate)
                    <= recentFileWindow
        }

        let transcriptAgents = fileStates
            .compactMap { url, state -> RunningAgent? in
                guard state.isActive,
                      now.timeIntervalSince(state.modificationDate)
                        <= activeSilenceTimeout
                else {
                    return nil
                }

                return RunningAgent(
                    kind: state.kind,
                    sessionID: state.sessionID,
                    activityLogPath: url.path,
                    source: .transcriptFallback
                )
            }

        var mergedAgents: [String: RunningAgent] = [:]

        for agent in transcriptAgents {
            let key = AgentSessionKey(
                kind: agent.kind,
                sessionID: agent.sessionID
            )
            guard !hookSnapshot.authoritativeSessions.contains(key) else {
                continue
            }

            mergedAgents[agent.id] = agent
        }

        for agent in hookSnapshot.activeAgents {
            mergedAgents[agent.id] = agent
        }

        return mergedAgents.values.sorted {
            if $0.kind.rawValue == $1.kind.rawValue {
                return $0.sessionID < $1.sessionID
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    private func candidateLogs(
        now: Date
    ) -> [(url: URL, kind: AgentKind, format: AgentActivityLogFormat, size: UInt64, modificationDate: Date)] {
        let cutoff = now.addingTimeInterval(-recentFileWindow)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        var candidates: [
            (
                url: URL,
                kind: AgentKind,
                format: AgentActivityLogFormat,
                size: UInt64,
                modificationDate: Date
            )
        ] = []

        for root in logRoots {
            guard let enumerator = fileManager.enumerator(
                at: root.url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      let modificationDate = values.contentModificationDate,
                      modificationDate >= cutoff
                else {
                    continue
                }

                candidates.append(
                    (
                        url: url,
                        kind: root.kind,
                        format: root.format,
                        size: UInt64(max(0, values.fileSize ?? 0)),
                        modificationDate: modificationDate
                    )
                )
            }
        }

        return candidates
    }

    private func updateState(
        for candidate: (
            url: URL,
            kind: AgentKind,
            format: AgentActivityLogFormat,
            size: UInt64,
            modificationDate: Date
        )
    ) {
        if fileStates[candidate.url] == nil {
            var initialState = FileState(
                kind: candidate.kind,
                format: candidate.format,
                sessionID: sessionIdentifier(for: candidate.url)
            )
            initialState.modificationDate = candidate.modificationDate
            bootstrapState(
                &initialState,
                from: candidate.url,
                fileSize: candidate.size
            )
            fileStates[candidate.url] = initialState
            return
        }

        var state = fileStates[candidate.url]!

        if candidate.size < state.offset {
            state.offset = 0
            state.partialLine.removeAll(keepingCapacity: false)
            state.isActive = false
            bootstrapState(
                &state,
                from: candidate.url,
                fileSize: candidate.size
            )
            state.modificationDate = candidate.modificationDate
            fileStates[candidate.url] = state
            return
        }

        state.modificationDate = candidate.modificationDate

        guard candidate.size > state.offset,
              let handle = try? FileHandle(forReadingFrom: candidate.url)
        else {
            fileStates[candidate.url] = state
            return
        }

        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: state.offset)

            while let chunk = try handle.read(upToCount: 262_144),
                  !chunk.isEmpty
            {
                state.offset += UInt64(chunk.count)
                state.partialLine.append(chunk)
                consumeCompleteLines(in: &state)
            }
        } catch {
            fileStates[candidate.url] = state
            return
        }

        fileStates[candidate.url] = state
    }

    private func bootstrapState(
        _ state: inout FileState,
        from url: URL,
        fileSize: UInt64
    ) {
        state.offset = fileSize
        state.partialLine.removeAll(keepingCapacity: false)

        guard fileSize > 0,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return
        }

        defer {
            try? handle.close()
        }

        let patterns: [(data: Data, isActive: Bool)]
        switch state.format {
        case .codex:
            patterns = [
                (
                    Data(
                        #""type":"event_msg","payload":{"type":"task_started""#
                            .utf8
                    ),
                    true
                ),
                (
                    Data(
                        #""type":"event_msg","payload":{"type":"task_complete""#
                            .utf8
                    ),
                    false
                )
            ]

        case .claude:
            patterns = [
                (Data(#""type":"user","message":"#.utf8), true),
                (Data(#""stop_reason":"end_turn""#.utf8), false)
            ]
        }

        let overlapCount = max(
            0,
            (patterns.map(\.data.count).max() ?? 1) - 1
        )
        var cursor = fileSize
        var laterPrefix = Data()

        do {
            while cursor > 0 {
                let readCount = min(UInt64(262_144), cursor)
                cursor -= readCount
                try handle.seek(toOffset: cursor)
                guard let chunk = try handle.read(
                    upToCount: Int(readCount)
                ) else {
                    break
                }

                var searchWindow = chunk
                searchWindow.append(laterPrefix)

                var latestMatch: (
                    position: Data.Index,
                    isActive: Bool
                )?
                for pattern in patterns {
                    guard let range = searchWindow.range(
                        of: pattern.data,
                        options: .backwards
                    ) else {
                        continue
                    }

                    if latestMatch == nil
                        || range.lowerBound > latestMatch!.position
                    {
                        latestMatch = (
                            position: range.lowerBound,
                            isActive: pattern.isActive
                        )
                    }
                }

                if let latestMatch {
                    state.isActive = latestMatch.isActive
                    return
                }

                laterPrefix = Data(chunk.prefix(overlapCount))
            }
        } catch {
            state.isActive = false
        }
    }

    private func sessionIdentifier(for url: URL) -> String {
        let filename = url.deletingPathExtension().lastPathComponent
        guard filename.count >= 36 else {
            return filename
        }

        return String(filename.suffix(36))
    }

    private func consumeCompleteLines(in state: inout FileState) {
        while let newlineIndex = state.partialLine.firstIndex(of: 0x0A) {
            let line = Data(state.partialLine[..<newlineIndex])
            let removalEnd = state.partialLine.index(after: newlineIndex)
            state.partialLine.removeSubrange(..<removalEnd)

            guard !line.isEmpty else {
                continue
            }

            state.isActive = AgentActivityLineParser.updatedState(
                currentState: state.isActive,
                line: line,
                format: state.format
            )
        }
    }
}

private struct ActivityEnvelope: Decodable {
    let type: String?
    let payload: ActivityPayload?
    let message: ActivityMessage?
}

private struct ActivityPayload: Decodable {
    let type: String?
}

private struct ActivityMessage: Decodable {
    let stopReason: String?

    private enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
    }
}
