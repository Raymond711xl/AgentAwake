import Foundation

public protocol AgentDetecting: Sendable {
    func runningAgents(
        forceReconciliation: Bool
    ) -> [RunningAgent]
}

public extension AgentDetecting {
    func runningAgents() -> [RunningAgent] {
        runningAgents(forceReconciliation: false)
    }
}

public struct AgentDetectionMetrics: Equatable, Sendable {
    public let fullReconciliationCount: Int
    public let targetedFileUpdateCount: Int
    public let cachedSessionCount: Int
    public let bufferedByteCount: Int
    public let monitoredPathCount: Int
    public let lastFullReconciliationAt: Date?

    public init(
        fullReconciliationCount: Int,
        targetedFileUpdateCount: Int,
        cachedSessionCount: Int,
        bufferedByteCount: Int,
        monitoredPathCount: Int,
        lastFullReconciliationAt: Date?
    ) {
        self.fullReconciliationCount = fullReconciliationCount
        self.targetedFileUpdateCount = targetedFileUpdateCount
        self.cachedSessionCount = cachedSessionCount
        self.bufferedByteCount = bufferedByteCount
        self.monitoredPathCount = monitoredPathCount
        self.lastFullReconciliationAt = lastFullReconciliationAt
    }
}

public enum AgentActivityLineParser {
    public static func updatedState(
        currentState: Bool,
        line: Data,
        format: AgentActivityLogFormat
    ) -> Bool {
        updatedState(
            currentState: currentState,
            line: line,
            patterns: bootstrapPatterns(for: format)
        )
    }

    public static func updatedState(
        currentState: Bool,
        line: Data,
        patterns: [AgentActivityPattern]
    ) -> Bool {
        var latest: (position: Data.Index, isActive: Bool)?
        for pattern in patterns {
            guard let range = line.range(
                of: pattern.data,
                options: .backwards
            ) else {
                continue
            }
            if latest == nil || range.lowerBound > latest!.position {
                latest = (range.lowerBound, pattern.isActive)
            }
        }
        return latest?.isActive ?? currentState
    }

    public static func bootstrapPatterns(
        for format: AgentActivityLogFormat
    ) -> [AgentActivityPattern] {
        switch format {
        case .codex:
            return [
                AgentActivityPattern(
                    data: Data(
                        #""type":"event_msg","payload":{"type":"task_started""#
                            .utf8
                    ),
                    isActive: true
                ),
                AgentActivityPattern(
                    data: Data(
                        #""type":"event_msg","payload":{"type":"task_complete""#
                            .utf8
                    ),
                    isActive: false
                )
            ]
        case .claude:
            return [
                AgentActivityPattern(
                    data: Data(#""type":"user","message":"#.utf8),
                    isActive: true
                ),
                AgentActivityPattern(
                    data: Data(#""stop_reason":"end_turn""#.utf8),
                    isActive: false
                )
            ]
        }
    }
}

public final class SystemAgentDetector: AgentDetecting, @unchecked Sendable {
    private struct Candidate {
        let url: URL
        let adapterIndex: Int
        let kind: AgentKind
        let size: UInt64
        let modificationDate: Date
        let wasActive: Bool
    }

    private struct FileState {
        let adapterIndex: Int
        let kind: AgentKind
        let sessionID: String
        var offset: UInt64 = 0
        var partialLine = Data()
        var isActive = false
        var modificationDate = Date.distantPast
    }

    private let fileManager: FileManager
    private let adapters: [any AgentActivityAdapter]
    private let recentFileWindow: TimeInterval
    private let activeSilenceTimeout: TimeInterval
    private let hookActivityStore: AgentHookActivityStore
    private let maximumCachedSessions: Int
    private let maximumTotalBufferBytes: Int
    private let maximumPartialLineBytes: Int
    private let bootstrapReadLimit: UInt64
    private let lock = NSLock()

    private var fileStates: [URL: FileState] = [:]
    private var dirtyURLs: Set<URL> = []
    private var needsFullReconciliation = true
    private var fullReconciliationCount = 0
    private var targetedFileUpdateCount = 0
    private var lastFullReconciliationAt: Date?
    private var eventMonitor: FileSystemEventMonitor?
    private var eventHandler: (@Sendable () -> Void)?
    private var monitoredPaths: Set<String> = []
    private var eventMonitorNeedsRestart = false
    private var monitoredPathCount = 0

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        hookActivityDirectory: URL? = nil,
        adapters: [any AgentActivityAdapter]? = nil,
        recentFileWindow: TimeInterval = 86_400,
        activeSilenceTimeout: TimeInterval = 1_800,
        hookLeaseTimeout: TimeInterval = 1_800,
        maximumCachedSessions: Int = 128,
        maximumTotalBufferBytes: Int = 1_048_576,
        maximumPartialLineBytes: Int = 65_536,
        bootstrapReadLimit: UInt64 = 4_194_304,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.adapters = adapters
            ?? BuiltInAgentAdapters.localTranscriptAdapters(
                homeDirectory: homeDirectory
            )
        self.recentFileWindow = recentFileWindow
        self.activeSilenceTimeout = activeSilenceTimeout
        self.maximumCachedSessions = min(
            max(1, maximumCachedSessions),
            128
        )
        self.maximumTotalBufferBytes = min(
            max(4_096, maximumTotalBufferBytes),
            1_048_576
        )
        self.maximumPartialLineBytes = min(
            max(1_024, maximumPartialLineBytes),
            65_536
        )
        self.bootstrapReadLimit = min(
            max(262_144, bootstrapReadLimit),
            4_194_304
        )
        self.hookActivityStore = AgentHookActivityStore(
            rootDirectory: hookActivityDirectory
                ?? AgentHookActivityStore.defaultRootDirectory(
                    homeDirectory: homeDirectory
                ),
            activeLeaseTimeout: hookLeaseTimeout,
            maximumLeaseRecords: maximumCachedSessions,
            fileManager: fileManager
        )
    }

    deinit {
        eventMonitor?.stop()
    }

    public func runningAgents(
        forceReconciliation: Bool = false
    ) -> [RunningAgent] {
        refreshEventMonitorConfigurationIfNeeded()
        let now = Date()
        let hookSnapshot = hookActivityStore.snapshot(now: now)

        lock.lock()
        if forceReconciliation {
            needsFullReconciliation = true
        }

        if needsFullReconciliation {
            reconcileAllLogs(now: now)
        } else {
            updateDirtyLogs(now: now)
        }

        pruneFileStates(now: now)
        enforceResourceLimits()
        let transcriptAgents = activeTranscriptAgents(now: now)
        let merged = merge(
            transcriptAgents: transcriptAgents,
            hookSnapshot: hookSnapshot
        )
        lock.unlock()

        return merged
    }

    public func startMonitoring(
        onChange: @escaping @Sendable () -> Void
    ) {
        stopMonitoring()
        try? hookActivityStore.prepareDirectory()

        lock.lock()
        eventHandler = onChange
        lock.unlock()
        refreshEventMonitorConfigurationIfNeeded(force: true)
    }

    public func stopMonitoring() {
        lock.lock()
        let monitor = eventMonitor
        eventMonitor = nil
        eventHandler = nil
        monitoredPaths.removeAll(keepingCapacity: false)
        eventMonitorNeedsRestart = false
        monitoredPathCount = 0
        lock.unlock()
        monitor?.stop()
    }

    public func recordFileEvents(_ batch: FileSystemActivityBatch) {
        var shouldNotify = batch.requiresFullReconciliation

        lock.lock()
        if batch.requiresFullReconciliation {
            needsFullReconciliation = true
            eventMonitorNeedsRestart = true
        }

        for rawURL in batch.urls {
            let url = rawURL.standardizedFileURL
            if isWithin(url, root: hookActivityStore.rootDirectory) {
                shouldNotify = true
                continue
            }

            if adapterDetails(for: url) != nil {
                if url.pathExtension == "jsonl" {
                    if !needsFullReconciliation,
                       dirtyURLs.count < maximumCachedSessions * 2
                    {
                        dirtyURLs.insert(url)
                    } else if dirtyURLs.count >= maximumCachedSessions * 2 {
                        dirtyURLs.removeAll(keepingCapacity: true)
                        needsFullReconciliation = true
                    }
                } else {
                    needsFullReconciliation = true
                }
                shouldNotify = true
                continue
            }

            if isWithinAnyWatchRoot(url) {
                needsFullReconciliation = true
                shouldNotify = true
            }
        }

        let handler = shouldNotify ? eventHandler : nil
        lock.unlock()
        handler?()
    }

    public func metrics() -> AgentDetectionMetrics {
        lock.lock()
        defer { lock.unlock() }
        return AgentDetectionMetrics(
            fullReconciliationCount: fullReconciliationCount,
            targetedFileUpdateCount: targetedFileUpdateCount,
            cachedSessionCount: fileStates.count,
            bufferedByteCount: fileStates.values.reduce(0) {
                $0 + $1.partialLine.count
            },
            monitoredPathCount: monitoredPathCount,
            lastFullReconciliationAt: lastFullReconciliationAt
        )
    }

    private func monitoringURLs() -> [URL] {
        var urls = adapters
            .filter { $0.capabilities.contains(.automaticLocal) }
            .flatMap(\.watchRoots)
        urls.append(hookActivityStore.rootDirectory)
        return Array(
            Dictionary(
                grouping: urls.filter { directoryExists($0) },
                by: { $0.standardizedFileURL.path }
            ).values.compactMap(\.first)
        ).sorted { $0.path < $1.path }
    }

    private func refreshEventMonitorConfigurationIfNeeded(
        force: Bool = false
    ) {
        let urls = monitoringURLs()
        let paths = Set(urls.map { $0.standardizedFileURL.path })

        lock.lock()
        guard eventHandler != nil else {
            lock.unlock()
            return
        }
        if !force,
           eventMonitor != nil,
           paths == monitoredPaths,
           !eventMonitorNeedsRestart
        {
            lock.unlock()
            return
        }

        let previousMonitor = eventMonitor
        if paths != monitoredPaths {
            needsFullReconciliation = true
        }
        eventMonitor = nil
        monitoredPaths.removeAll(keepingCapacity: false)
        eventMonitorNeedsRestart = false
        monitoredPathCount = 0
        lock.unlock()

        previousMonitor?.stop()

        let monitor = FileSystemEventMonitor(urls: urls) { [weak self] batch in
            self?.recordFileEvents(batch)
        }
        let started = monitor.start()

        lock.lock()
        let shouldKeepMonitor = eventHandler != nil && started
        if shouldKeepMonitor {
            eventMonitor = monitor
            monitoredPaths = paths
            monitoredPathCount = paths.count
        } else if eventHandler != nil {
            // Native events are unavailable. The 60-second lease check will
            // retry this setup and perform a bounded reconciliation.
            needsFullReconciliation = true
        }
        lock.unlock()

        if !shouldKeepMonitor, started {
            monitor.stop()
        }
    }

    private func reconcileAllLogs(now: Date) {
        let candidates = candidateLogs(now: now)
        let candidateURLs = Set(candidates.map(\.url))

        for candidate in candidates {
            updateState(for: candidate)
            enforceBufferLimit()
        }

        fileStates = fileStates.filter { url, state in
            candidateURLs.contains(url)
                || now.timeIntervalSince(state.modificationDate)
                    <= recentFileWindow
        }
        dirtyURLs.removeAll(keepingCapacity: true)
        needsFullReconciliation = false
        fullReconciliationCount += 1
        lastFullReconciliationAt = now
    }

    private func updateDirtyLogs(now: Date) {
        let urls = dirtyURLs
        dirtyURLs.removeAll(keepingCapacity: true)
        guard !urls.isEmpty else {
            return
        }

        for url in urls {
            guard let candidate = candidate(for: url, now: now) else {
                fileStates.removeValue(forKey: url)
                continue
            }
            updateState(for: candidate)
            enforceBufferLimit()
            targetedFileUpdateCount += 1
        }
    }

    private func candidateLogs(now: Date) -> [Candidate] {
        let cutoff = now.addingTimeInterval(-recentFileWindow)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        let maximumCandidates = maximumCachedSessions * 2
        var candidates: [Candidate] = []

        for (adapterIndex, adapter) in adapters.enumerated() {
            guard adapter.capabilities.contains(.automaticLocal) else {
                continue
            }
            for root in adapter.logRoots {
                guard let enumerator = fileManager.enumerator(
                    at: root,
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
                        Candidate(
                            url: url.standardizedFileURL,
                            adapterIndex: adapterIndex,
                            kind: adapter.identity,
                            size: UInt64(max(0, values.fileSize ?? 0)),
                            modificationDate: modificationDate,
                            wasActive: isStateCurrentlyActive(
                                fileStates[url.standardizedFileURL],
                                now: now
                            )
                        )
                    )

                    if candidates.count >= maximumCandidates * 2 {
                        candidates = trimmedCandidates(
                            candidates,
                            limit: maximumCandidates
                        )
                    }
                }
            }
        }

        return trimmedCandidates(candidates, limit: maximumCandidates)
    }

    private func trimmedCandidates(
        _ candidates: [Candidate],
        limit: Int
    ) -> [Candidate] {
        guard candidates.count > limit else {
            return candidates
        }
        return Array(
            candidates.sorted {
                if $0.wasActive != $1.wasActive {
                    return $0.wasActive && !$1.wasActive
                }
                return $0.modificationDate > $1.modificationDate
            }.prefix(limit)
        )
    }

    private func candidate(for url: URL, now: Date) -> Candidate? {
        guard url.pathExtension == "jsonl",
              let details = adapterDetails(for: url),
              let values = try? url.resourceValues(forKeys: [
                  .isRegularFileKey,
                  .contentModificationDateKey,
                  .fileSizeKey
              ]),
              values.isRegularFile == true,
              let modificationDate = values.contentModificationDate,
              modificationDate >= now.addingTimeInterval(-recentFileWindow)
        else {
            return nil
        }

        return Candidate(
            url: url.standardizedFileURL,
            adapterIndex: details.index,
            kind: details.adapter.identity,
            size: UInt64(max(0, values.fileSize ?? 0)),
            modificationDate: modificationDate,
            wasActive: isStateCurrentlyActive(
                fileStates[url.standardizedFileURL],
                now: now
            )
        )
    }

    private func isStateCurrentlyActive(
        _ state: FileState?,
        now: Date
    ) -> Bool {
        guard let state, state.isActive else {
            return false
        }
        return now.timeIntervalSince(state.modificationDate)
            <= activeSilenceTimeout
    }

    private func adapterDetails(
        for url: URL
    ) -> (index: Int, adapter: any AgentActivityAdapter)? {
        for (index, adapter) in adapters.enumerated() {
            if adapter.capabilities.contains(.automaticLocal),
               adapter.logRoots.contains(where: { isWithin(url, root: $0) })
            {
                return (index, adapter)
            }
        }
        return nil
    }

    private func updateState(for candidate: Candidate) {
        if fileStates[candidate.url] == nil {
            var initialState = FileState(
                adapterIndex: candidate.adapterIndex,
                kind: candidate.kind,
                sessionID: adapters[candidate.adapterIndex]
                    .sessionIdentifier(for: candidate.url)
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
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.offset)
            while let chunk = try handle.read(upToCount: 262_144),
                  !chunk.isEmpty
            {
                state.offset += UInt64(chunk.count)
                state.partialLine.append(chunk)
                consumeCompleteLines(in: &state)
                trimOversizedPartialLine(in: &state)
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
        defer { try? handle.close() }

        let patterns = adapters[state.adapterIndex].bootstrapPatterns
        let overlapCount = max(
            0,
            (patterns.map(\.data.count).max() ?? 1) - 1
        )
        let lowerBound = fileSize > bootstrapReadLimit
            ? fileSize - bootstrapReadLimit
            : 0
        var cursor = fileSize
        var laterPrefix = Data()

        do {
            while cursor > lowerBound {
                let readCount = min(UInt64(262_144), cursor - lowerBound)
                cursor -= readCount
                try handle.seek(toOffset: cursor)
                guard let chunk = try handle.read(
                    upToCount: Int(readCount)
                ) else {
                    break
                }

                var searchWindow = chunk
                searchWindow.append(laterPrefix)
                if let latest = latestActivityState(
                    in: searchWindow,
                    adapterIndex: state.adapterIndex
                ) {
                    state.isActive = latest
                    return
                }
                laterPrefix = Data(chunk.prefix(overlapCount))
            }
        } catch {
            state.isActive = false
        }
    }

    private func consumeCompleteLines(in state: inout FileState) {
        while let newlineIndex = state.partialLine.firstIndex(of: 0x0A) {
            let line = Data(state.partialLine[..<newlineIndex])
            let removalEnd = state.partialLine.index(after: newlineIndex)
            state.partialLine.removeSubrange(..<removalEnd)
            guard !line.isEmpty else {
                continue
            }
            state.isActive = adapters[state.adapterIndex]
                .updatedActivityState(
                    currentState: state.isActive,
                    line: line
                )
        }
    }

    private func trimOversizedPartialLine(in state: inout FileState) {
        guard state.partialLine.count > maximumPartialLineBytes else {
            return
        }
        if let latest = latestActivityState(
            in: state.partialLine,
            adapterIndex: state.adapterIndex
        ) {
            state.isActive = latest
        }
        let overlap = max(
            256,
            adapters[state.adapterIndex].bootstrapPatterns
                .map(\.data.count)
                .max() ?? 256
        )
        state.partialLine = Data(state.partialLine.suffix(overlap))
    }

    private func pruneFileStates(now: Date) {
        for (url, var state) in fileStates where state.isActive {
            if now.timeIntervalSince(state.modificationDate)
                > activeSilenceTimeout
            {
                state.isActive = false
                fileStates[url] = state
            }
        }
        fileStates = fileStates.filter { _, state in
            now.timeIntervalSince(state.modificationDate) <= recentFileWindow
        }
    }

    private func enforceResourceLimits() {
        if fileStates.count > maximumCachedSessions {
            let retainedURLs = Set(
                fileStates.sorted {
                    if $0.value.isActive != $1.value.isActive {
                        return $0.value.isActive && !$1.value.isActive
                    }
                    return $0.value.modificationDate
                        > $1.value.modificationDate
                }
                .prefix(maximumCachedSessions)
                .map(\.key)
            )
            fileStates = fileStates.filter { retainedURLs.contains($0.key) }
        }

        enforceBufferLimit()
    }

    private func enforceBufferLimit() {
        var bufferedBytes = fileStates.values.reduce(0) {
            $0 + $1.partialLine.count
        }
        guard bufferedBytes > maximumTotalBufferBytes else {
            return
        }

        for url in fileStates.keys.sorted(by: {
            let lhs = fileStates[$0]?.modificationDate ?? .distantPast
            let rhs = fileStates[$1]?.modificationDate ?? .distantPast
            return lhs < rhs
        }) {
            guard var state = fileStates[url], !state.partialLine.isEmpty else {
                continue
            }
            bufferedBytes -= state.partialLine.count
            state.partialLine.removeAll(keepingCapacity: false)
            fileStates[url] = state
            if bufferedBytes <= maximumTotalBufferBytes {
                break
            }
        }
    }

    private func activeTranscriptAgents(now: Date) -> [RunningAgent] {
        fileStates.compactMap { url, state in
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
                source: .automaticLocal
            )
        }
    }

    private func merge(
        transcriptAgents: [RunningAgent],
        hookSnapshot: AgentHookSnapshot
    ) -> [RunningAgent] {
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
        return mergedAgents.values.sorted(by: Self.agentSort)
    }

    private func latestActivityState(
        in data: Data,
        adapterIndex: Int
    ) -> Bool? {
        var latestMatch: (position: Data.Index, isActive: Bool)?
        for pattern in adapters[adapterIndex].bootstrapPatterns {
            guard let range = data.range(of: pattern.data, options: .backwards)
            else {
                continue
            }
            if latestMatch == nil || range.lowerBound > latestMatch!.position {
                latestMatch = (range.lowerBound, pattern.isActive)
            }
        }
        return latestMatch?.isActive
    }

    private func isWithinAnyWatchRoot(_ url: URL) -> Bool {
        adapters.contains { adapter in
            adapter.capabilities.contains(.automaticLocal)
                && adapter.watchRoots.contains { isWithin(url, root: $0) }
        }
    }

    private func isWithin(_ url: URL, root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
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
