import AgentAwakeCore
import AgentAwakeSetupCore
import Darwin
import Foundation

private var failures: [String] = []

private func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    if !condition() {
        failures.append(message)
    }
}

private struct MarkerAgentAdapter: AgentActivityAdapter {
    let identity = AgentKind(
        identifier: "marker-agent",
        displayName: "Marker Agent"
    )!
    let logRoots: [URL]
    let watchRoots: [URL]
    let capabilities: Set<AgentDetectionCapability> = [.automaticLocal]

    var bootstrapPatterns: [AgentActivityPattern] {
        [
            AgentActivityPattern(
                data: Data("BEGIN_AGENT".utf8),
                isActive: true
            ),
            AgentActivityPattern(
                data: Data("END_AGENT".utf8),
                isActive: false
            )
        ]
    }

    init(root: URL) {
        logRoots = [root]
        watchRoots = [root]
    }

    func updatedActivityState(
        currentState: Bool,
        line: Data
    ) -> Bool {
        if line.range(of: Data("BEGIN_AGENT".utf8)) != nil {
            return true
        }
        if line.range(of: Data("END_AGENT".utf8)) != nil {
            return false
        }
        return currentState
    }

    func sessionIdentifier(for activityURL: URL) -> String {
        "marker:\(activityURL.deletingPathExtension().lastPathComponent)"
    }
}

private func testExtensibleAgentIdentityAndEvents() {
    guard let custom = AgentKind(
        identifier: "Cursor_CLI",
        displayName: "Cursor CLI"
    ) else {
        failures.append("合法的自定义 Agent 身份应可创建")
        return
    }

    expect(custom.identifier == "cursor_cli", "Provider ID 应规范为小写")
    expect(custom.displayName == "Cursor CLI", "显示名称应保持原文")
    expect(
        custom == AgentKind(
            identifier: "cursor_cli",
            displayName: "Cursor Agent"
        ),
        "同一 Provider ID 不应因显示名称变化而失去身份一致性"
    )
    expect(
        AgentKind(identifier: "-invalid") == nil,
        "Provider ID 必须以字母或数字开头"
    )
    expect(
        AgentKind(identifier: "bad/provider") == nil,
        "Provider ID 不应接受路径字符"
    )

    let legacyCodex = try? JSONDecoder().decode(
        AgentKind.self,
        from: Data(#""Codex""#.utf8)
    )
    expect(legacyCodex == .codex, "旧版字符串身份应继续解码")

    if let encoded = try? JSONEncoder().encode(custom),
       let decoded = try? JSONDecoder().decode(
           AgentKind.self,
           from: encoded
       )
    {
        expect(decoded == custom, "自定义 Agent 身份应可往返编码")
        expect(
            decoded.displayName == custom.displayName,
            "身份编码不应丢失显示名称"
        )
    } else {
        failures.append("自定义 Agent 身份编码失败")
    }

    let occurredAt = Date(timeIntervalSince1970: 1_234)
    let event = AgentActivityEvent(
        provider: custom,
        sessionID: "cursor-session",
        activityID: "run-1",
        kind: .start,
        source: .preciseBridge,
        occurredAt: occurredAt
    )
    expect(event?.occurredAt == occurredAt, "统一事件应保留发生时间")
    expect(event?.source.confidence == .precise, "Bridge 事件应为精确来源")
    expect(
        AgentActivityEvent(
            provider: custom,
            sessionID: "bad\u{0000}session",
            kind: .start,
            source: .preciseBridge
        ) == nil,
        "统一事件应拒绝控制字符"
    )
}

private func testCustomAdapterExtensionPoint() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeCustomAdapterTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: root)
    }
    try? fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    let log = root
        .appendingPathComponent("custom-session")
        .appendingPathExtension("jsonl")
    try? Data("BEGIN_AGENT\n".utf8).write(to: log)

    let adapter = MarkerAgentAdapter(root: root)
    let detector = SystemAgentDetector(
        hookActivityDirectory: root.appendingPathComponent("hooks"),
        adapters: [adapter]
    )
    let active = detector.runningAgents(forceReconciliation: true)
    expect(active.first?.kind == adapter.identity, "自定义适配器应被核心发现")
    expect(
        active.first?.sessionID == "marker:custom-session",
        "会话标识规则应由适配器控制"
    )

    if let handle = try? FileHandle(forWritingTo: log) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("END_AGENT\n".utf8))
        try? handle.close()
    }
    detector.recordFileEvents(
        FileSystemActivityBatch(
            urls: [log],
            requiresFullReconciliation: false
        )
    )
    expect(
        detector.runningAgents().isEmpty,
        "自定义适配器应独立解析结束状态"
    )
}

private func testProtectionSession() {
    let now = Date(timeIntervalSince1970: 1_000)

    var offSession = ProtectionSession(mode: .off)
    let offEffects = offSession.setEnabled(
        true,
        agentCount: 1,
        now: now
    )
    expect(!offSession.isEnabled, "未开启档不应创建运行会话")
    expect(!offSession.isProtecting, "未开启档不应接管休眠权限")
    expect(offEffects.isEmpty, "未开启档不应产生电源效果")

    var timedSession = ProtectionSession(mode: .thirtyMinutes)
    let timedEffects = timedSession.setEnabled(
        true,
        agentCount: 0,
        now: now
    )
    expect(timedSession.isEnabled, "定时模式应正常开启")
    expect(timedSession.isProtecting, "定时模式应立即开始保护")
    expect(
        timedEffects == [.acquire(timeout: 1_800)],
        "30 分钟模式应立即创建 30 分钟断言"
    )

    var waitingSession = ProtectionSession(mode: .agent)
    let waitingEffects = waitingSession.setEnabled(
        true,
        agentCount: 0,
        now: now
    )
    expect(waitingSession.isEnabled, "Agent 档无任务时应保持等待")
    expect(!waitingSession.isProtecting, "无 Agent 时不应创建保护")
    expect(waitingEffects.isEmpty, "无 Agent 时不应产生电源效果")

    var activeSession = ProtectionSession(mode: .agent)
    _ = activeSession.setEnabled(true, agentCount: 0, now: now)
    let startEffects = activeSession.updateAgentCount(1, now: now)
    expect(
        startEffects == [.acquire(timeout: 120)],
        "首次检测到 Agent 应创建短租约断言"
    )

    var finishedSession = ProtectionSession(
        mode: .agent,
        agentEndGrace: 5
    )
    _ = finishedSession.setEnabled(true, agentCount: 1, now: now)
    _ = finishedSession.updateAgentCount(
        0,
        now: now.addingTimeInterval(10)
    )
    let finishEffects = finishedSession.tick(
        now: now.addingTimeInterval(15)
    )
    expect(
        finishEffects == [
            .release,
            .restartSystemIdleCountdown,
            .agentFinished
        ],
        "Agent 结束后应释放并恢复系统计时"
    )
    expect(finishedSession.isEnabled, "Agent 结束后 Agent 档应保持监听")
    expect(!finishedSession.isProtecting, "Agent 结束后不应继续保护")
    let nextAgentEffects = finishedSession.updateAgentCount(
        1,
        now: now.addingTimeInterval(20)
    )
    expect(
        nextAgentEffects == [.acquire(timeout: 120)],
        "新 Agent 出现时应再次开始保护"
    )

    var returnedSession = ProtectionSession(
        mode: .agent,
        agentEndGrace: 5
    )
    _ = returnedSession.setEnabled(true, agentCount: 1, now: now)
    _ = returnedSession.updateAgentCount(
        0,
        now: now.addingTimeInterval(10)
    )
    let returnEffects = returnedSession.updateAgentCount(
        1,
        now: now.addingTimeInterval(12)
    )
    expect(returnEffects.isEmpty, "防抖期内 Agent 返回不应释放")
    expect(returnedSession.isProtecting, "Agent 返回后应继续保护")

    var renewalSession = ProtectionSession(
        mode: .agent,
        agentAssertionLease: 120,
        agentAssertionRenewalInterval: 60
    )
    _ = renewalSession.setEnabled(true, agentCount: 1, now: now)
    let renewalEffects = renewalSession.tick(
        now: now.addingTimeInterval(60)
    )
    expect(
        renewalEffects == [.renew(timeout: 120)],
        "Agent 长任务应续租短时断言"
    )

    var elapsedSession = ProtectionSession(mode: .thirtyMinutes)
    _ = elapsedSession.setEnabled(true, agentCount: 0, now: now)
    let elapsedEffects = elapsedSession.tick(
        now: now.addingTimeInterval(1_800)
    )
    expect(
        elapsedEffects == [.release, .autoDisabled(.durationElapsed)],
        "时长到期后应释放并返回未开启档"
    )

    var manualSession = ProtectionSession(mode: .twoHours)
    _ = manualSession.setEnabled(true, agentCount: 2, now: now)
    let manualEffects = manualSession.setEnabled(
        false,
        agentCount: 2,
        now: now.addingTimeInterval(3)
    )
    expect(manualEffects == [.release], "手动关闭应立即释放")

    var exclusiveSession = ProtectionSession(mode: .oneHour)
    _ = exclusiveSession.setEnabled(true, agentCount: 0, now: now)
    exclusiveSession.selectMode(.agent)
    expect(
        exclusiveSession.mode == .oneHour,
        "运行中不应切换到另一种防休眠模式"
    )
}

private func hookEventData(
    sessionID: String,
    eventName: String,
    turnID: String? = nil,
    promptID: String? = nil
) -> Data {
    var object: [String: Any] = [
        "session_id": sessionID,
        "hook_event_name": eventName
    ]
    if let turnID {
        object["turn_id"] = turnID
    }
    if let promptID {
        object["prompt_id"] = promptID
    }
    return try! JSONSerialization.data(withJSONObject: object)
}

private func testHookActivityStore() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeHookTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: root)
    }

    let now = Date(timeIntervalSince1970: 2_000)
    let store = AgentHookActivityStore(
        rootDirectory: root,
        activeLeaseTimeout: 30,
        inactiveAuthorityWindow: 300
    )
    let sessionID = "codex-session"
    let turnID = "codex-turn"

    let startAction = try? store.handle(
        provider: .codex,
        input: hookEventData(
            sessionID: sessionID,
            eventName: "UserPromptSubmit",
            turnID: turnID
        ),
        now: now
    )
    expect(startAction == .activate, "UserPromptSubmit 应建立运行租约")

    let activeSnapshot = store.snapshot(now: now)
    expect(activeSnapshot.activeAgents.count == 1, "Hook 租约应识别一个 Agent")
    expect(
        activeSnapshot.activeAgents.first?.source == .lifecycleHook,
        "Hook Agent 应标记为生命周期事件来源"
    )

    let heartbeatAction = try? store.handle(
        provider: .codex,
        input: hookEventData(
            sessionID: sessionID,
            eventName: "PostToolUse",
            turnID: turnID
        ),
        now: now.addingTimeInterval(20)
    )
    expect(heartbeatAction == .heartbeat, "工具事件应续租")
    expect(
        store.snapshot(
            now: now.addingTimeInterval(40)
        ).activeAgents.count == 1,
        "续租后 Agent 应继续保持活动"
    )

    let stopAction = try? store.handle(
        provider: .codex,
        input: hookEventData(
            sessionID: sessionID,
            eventName: "Stop",
            turnID: turnID
        ),
        now: now.addingTimeInterval(45)
    )
    expect(stopAction == .deactivate, "Stop 应释放运行租约")

    let stoppedSnapshot = store.snapshot(
        now: now.addingTimeInterval(46)
    )
    expect(stoppedSnapshot.activeAgents.isEmpty, "Stop 后不应有活动 Agent")
    expect(
        stoppedSnapshot.authoritativeSessions.contains(
            AgentSessionKey(kind: .codex, sessionID: sessionID)
        ),
        "Stop 状态应覆盖同会话的不稳定日志兜底"
    )

    let staleRoot = root.appendingPathComponent(
        "stale",
        isDirectory: true
    )
    let staleStore = AgentHookActivityStore(
        rootDirectory: staleRoot,
        activeLeaseTimeout: 30,
        inactiveAuthorityWindow: 300
    )
    _ = try? staleStore.handle(
        provider: .claude,
        input: hookEventData(
            sessionID: "claude-session",
            eventName: "UserPromptSubmit",
            promptID: "claude-prompt"
        ),
        now: now
    )
    let staleSnapshot = staleStore.snapshot(
        now: now.addingTimeInterval(31)
    )
    expect(staleSnapshot.activeAgents.isEmpty, "失联租约必须自动失效")
    expect(
        staleSnapshot.authoritativeSessions.isEmpty,
        "失联租约不应压制日志兜底"
    )
}

private func testLegacyLeaseAndCustomBridge() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeLegacyLeaseTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: root)
    }
    try? fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let now = Date(timeIntervalSince1970: 3_000)
    let legacyRecord: [String: Any] = [
        "schemaVersion": 1,
        "kind": "Codex",
        "sessionID": "legacy-session",
        "activityID": "legacy-turn",
        "state": "active",
        "lastEventName": "PostToolUse",
        "updatedAt": ISO8601DateFormatter().string(from: now)
    ]
    if let data = try? JSONSerialization.data(withJSONObject: legacyRecord) {
        try? data.write(
            to: root.appendingPathComponent("legacy.json"),
            options: .atomic
        )
    }

    let store = AgentHookActivityStore(
        rootDirectory: root,
        activeLeaseTimeout: 60,
        inactiveAuthorityWindow: 300
    )
    let legacySnapshot = store.snapshot(now: now)
    expect(
        legacySnapshot.activeAgents.first?.kind == .codex,
        "旧版 Codex 租约应继续识别"
    )
    expect(
        legacySnapshot.activeAgents.first?.source == .preciseHook,
        "旧版租约应迁移为精确 Hook 来源"
    )

    let futureRecord: [String: Any] = [
        "schemaVersion": 1,
        "kind": "Claude",
        "sessionID": "future-session",
        "activityID": "future-turn",
        "state": "active",
        "lastEventName": "PostToolUse",
        "updatedAt": ISO8601DateFormatter().string(
            from: now.addingTimeInterval(86_400)
        )
    ]
    let futureURL = root.appendingPathComponent("future.json")
    if let data = try? JSONSerialization.data(withJSONObject: futureRecord) {
        try? data.write(to: futureURL, options: .atomic)
    }
    let futureSnapshot = store.snapshot(now: now)
    expect(
        !futureSnapshot.activeAgents.contains { $0.kind == .claude },
        "未来时间戳租约不应造成永久唤醒"
    )
    expect(
        !fileManager.fileExists(atPath: futureURL.path),
        "异常未来租约应从本地缓存清理"
    )

    let oversizedURL = root.appendingPathComponent("oversized.json")
    try? Data(repeating: 0x78, count: 20_000).write(to: oversizedURL)
    _ = store.snapshot(now: now)
    expect(
        !fileManager.fileExists(atPath: oversizedURL.path),
        "异常大租约文件不应进入内存"
    )

    guard let custom = AgentKind(
        identifier: "cursor",
        displayName: "Cursor"
    ),
    let start = AgentActivityEvent(
        provider: custom,
        sessionID: "cursor-session",
        activityID: "cursor-run",
        kind: .start,
        source: .preciseBridge,
        eventName: "BridgeStart",
        occurredAt: now
    ) else {
        failures.append("自定义 Bridge 测试事件创建失败")
        return
    }

    do {
        try store.handle(event: start, now: now)
    } catch {
        failures.append("Bridge start 写入失败：\(error.localizedDescription)")
    }
    let activeSnapshot = store.snapshot(now: now)
    let bridgeAgent = activeSnapshot.activeAgents.first {
        $0.kind.identifier == custom.identifier
    }
    expect(bridgeAgent?.kind.displayName == "Cursor", "Bridge 应保留显示名称")
    expect(
        bridgeAgent?.source == .preciseBridge,
        "Bridge 租约应标记为 preciseBridge"
    )

    guard let stop = AgentActivityEvent(
        provider: AgentKind(
            identifier: "cursor",
            displayName: "Cursor Agent"
        )!,
        sessionID: "cursor-session",
        activityID: "cursor-run",
        kind: .stop,
        source: .preciseBridge,
        eventName: "BridgeStop",
        occurredAt: now.addingTimeInterval(1)
    ) else {
        failures.append("自定义 Bridge stop 事件创建失败")
        return
    }
    do {
        try store.handle(
            event: stop,
            now: now.addingTimeInterval(1)
        )
    } catch {
        failures.append("Bridge stop 写入失败：\(error.localizedDescription)")
    }
    let stoppedSnapshot = store.snapshot(
        now: now.addingTimeInterval(2)
    )
    expect(
        stoppedSnapshot.activeAgents.allSatisfy {
            $0.kind.identifier != custom.identifier
        },
        "Bridge stop 应释放自定义 Agent"
    )
    expect(
        stoppedSnapshot.authoritativeSessions.contains(
            AgentSessionKey(kind: custom, sessionID: "cursor-session")
        ),
        "精确 stop 应对同一 Provider ID 保持权威"
    )
}

private func testHookOverridesTranscriptFallback() {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeDetectorTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: home)
    }

    let sessionID = "12345678-1234-1234-1234-123456789abc"
    let logDirectory = home
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("test", isDirectory: true)
    try? fileManager.createDirectory(
        at: logDirectory,
        withIntermediateDirectories: true
    )
    let logURL = logDirectory
        .appendingPathComponent(sessionID)
        .appendingPathExtension("jsonl")
    let activeLine = Data(
        (#"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n")
            .utf8
    )
    try? activeLine.write(to: logURL)

    let hookRoot = home.appendingPathComponent(
        "hook-activity",
        isDirectory: true
    )
    let detector = SystemAgentDetector(
        homeDirectory: home,
        hookActivityDirectory: hookRoot
    )
    let fallbackAgents = detector.runningAgents()
    expect(
        fallbackAgents.first?.source == .transcriptFallback,
        "无 Hook 状态时应保留零配置日志兜底"
    )

    let store = AgentHookActivityStore(rootDirectory: hookRoot)
    _ = try? store.handle(
        provider: .codex,
        input: hookEventData(
            sessionID: sessionID,
            eventName: "Stop",
            turnID: "turn-complete"
        )
    )

    expect(
        detector.runningAgents().isEmpty,
        "同一会话收到 Hook Stop 后应覆盖滞后的日志状态"
    )
}

private func testEventDrivenDetectorAndResourceBounds() {
    let fileManager = FileManager.default
    let home = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeEventDetectorTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: home)
    }

    let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
    let sessions = codexHome.appendingPathComponent(
        "sessions",
        isDirectory: true
    )
    try? fileManager.createDirectory(
        at: sessions,
        withIntermediateDirectories: true
    )
    let primaryLog = sessions
        .appendingPathComponent("primary-session")
        .appendingPathExtension("jsonl")
    try? Data(
        (#"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n")
            .utf8
    ).write(to: primaryLog)

    let hookRoot = home.appendingPathComponent(
        "hook-activity",
        isDirectory: true
    )
    let detector = SystemAgentDetector(
        homeDirectory: home,
        hookActivityDirectory: hookRoot,
        maximumCachedSessions: 4,
        maximumTotalBufferBytes: 4_096,
        maximumPartialLineBytes: 1_024
    )

    let firstResult = detector.runningAgents(forceReconciliation: true)
    let firstMetrics = detector.metrics()
    expect(firstResult.count == 1, "首次校准应发现 Codex 活动")
    expect(
        firstMetrics.fullReconciliationCount == 1,
        "首次检测应只执行一次完整校准"
    )
    expect(
        firstMetrics.monitoredPathCount == 0,
        "未显式启用 Agent 监听时不应创建文件事件流"
    )

    if let handle = try? FileHandle(forWritingTo: primaryLog) {
        _ = try? handle.seekToEnd()
        try? handle.write(
            contentsOf: Data(
                (#"{"type":"event_msg","payload":{"type":"task_complete"}}"# + "\n")
                    .utf8
            )
        )
        try? handle.close()
    }
    detector.recordFileEvents(
        FileSystemActivityBatch(
            urls: [primaryLog],
            requiresFullReconciliation: false
        )
    )
    let incrementalResult = detector.runningAgents()
    let incrementalMetrics = detector.metrics()
    expect(incrementalResult.isEmpty, "增量追加的结束事件应停止 Agent")
    expect(
        incrementalMetrics.fullReconciliationCount
            == firstMetrics.fullReconciliationCount,
        "普通文件追加不应触发递归校准"
    )
    expect(
        incrementalMetrics.targetedFileUpdateCount == 1,
        "普通文件追加应只更新目标日志"
    )

    let nestedDirectory = sessions.appendingPathComponent(
        "new-directory",
        isDirectory: true
    )
    try? fileManager.createDirectory(
        at: nestedDirectory,
        withIntermediateDirectories: true
    )
    let nestedLog = nestedDirectory
        .appendingPathComponent("nested-session")
        .appendingPathExtension("jsonl")
    try? Data(
        (#"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n")
            .utf8
    ).write(to: nestedLog)
    detector.recordFileEvents(
        FileSystemActivityBatch(
            urls: [nestedDirectory],
            requiresFullReconciliation: false
        )
    )
    let directoryResult = detector.runningAgents()
    expect(
        directoryResult.contains { $0.sessionID == "nested-session" },
        "新建日志目录应触发完整校准兜底"
    )

    let beforeDroppedEvent = detector.metrics().fullReconciliationCount
    detector.recordFileEvents(
        FileSystemActivityBatch(
            urls: [],
            requiresFullReconciliation: true
        )
    )
    _ = detector.runningAgents()
    expect(
        detector.metrics().fullReconciliationCount
            == beforeDroppedEvent + 1,
        "文件事件丢失标记应触发完整校准"
    )

    for index in 0..<12 {
        let log = sessions
            .appendingPathComponent("bounded-\(index)")
            .appendingPathExtension("jsonl")
        try? Data(
            (#"{"type":"event_msg","payload":{"type":"task_started"}}"# + "\n")
                .utf8
        ).write(to: log)
    }
    let boundedResult = detector.runningAgents(forceReconciliation: true)
    let boundedMetrics = detector.metrics()
    expect(
        boundedMetrics.cachedSessionCount <= 4,
        "会话缓存不得突破配置上限"
    )

    if let retainedLogPath = boundedResult.first?.activityLogPath,
       let handle = try? FileHandle(
           forWritingTo: URL(fileURLWithPath: retainedLogPath)
       )
    {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(repeating: 0x78, count: 32_768))
        try? handle.close()
        detector.recordFileEvents(
            FileSystemActivityBatch(
                urls: [URL(fileURLWithPath: retainedLogPath)],
                requiresFullReconciliation: false
            )
        )
        _ = detector.runningAgents()
    }
    expect(
        detector.metrics().bufferedByteCount <= 4_096,
        "异常长记录不得突破总增量缓冲区上限"
    )

    let nativeEvent = DispatchSemaphore(value: 0)
    detector.startMonitoring {
        nativeEvent.signal()
    }
    let initialMonitoredPathCount = detector.metrics().monitoredPathCount
    if initialMonitoredPathCount > 0 {
        expect(
            initialMonitoredPathCount == 2,
            "自动检测应只监听现有 Agent 根目录和租约目录（实际 \(initialMonitoredPathCount)）"
        )
        let eventProbe = sessions.appendingPathComponent("event-probe.tmp")
        try? Data("probe".utf8).write(to: eventProbe)
        expect(
            nativeEvent.wait(timeout: .now() + 4) == .success,
            "原生文件事件流应收到 Agent 目录变化"
        )
        _ = detector.runningAgents()
    }

    let claudeProjects = home
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("projects", isDirectory: true)
    try? fileManager.createDirectory(
        at: claudeProjects,
        withIntermediateDirectories: true
    )
    let claudeLog = claudeProjects
        .appendingPathComponent("claude-session")
        .appendingPathExtension("jsonl")
    try? Data(
        (#"{"type":"user","message":{"role":"user"}}"# + "\n").utf8
    ).write(to: claudeLog)
    let beforeNewRoot = detector.metrics().fullReconciliationCount
    let newRootResult = detector.runningAgents()
    expect(
        newRootResult.contains { $0.kind == .claude },
        "运行期间新出现的 Agent 根目录应在轻量检查后纳入检测"
    )
    expect(
        detector.metrics().fullReconciliationCount == beforeNewRoot + 1,
        "新增监听根目录应执行一次校准"
    )
    let expandedMonitoredPathCount = detector.metrics().monitoredPathCount
    if initialMonitoredPathCount > 0 {
        expect(
            expandedMonitoredPathCount == 3,
            "新增 Agent 应扩展同一个事件流（实际 \(expandedMonitoredPathCount)）"
        )
    } else {
        expect(
            expandedMonitoredPathCount == 0,
            "原生事件不可用时应保持退避校准模式"
        )
    }
    detector.stopMonitoring()
    expect(
        detector.metrics().monitoredPathCount == 0,
        "停止 Agent 模式后应释放文件事件流"
    )
}

private func testAgentActivityParsing() {
    let codexStart = Data(
        #"{"type":"event_msg","payload":{"type":"task_started"}}"#.utf8
    )
    let codexComplete = Data(
        #"{"type":"event_msg","payload":{"type":"task_complete"}}"#.utf8
    )
    expect(
        AgentActivityLineParser.updatedState(
            currentState: false,
            line: codexStart,
            format: .codex
        ),
        "Codex task_started 应标记为工作中"
    )
    expect(
        !AgentActivityLineParser.updatedState(
            currentState: true,
            line: codexComplete,
            format: .codex
        ),
        "Codex task_complete 应标记为已结束"
    )

    let claudeUser = Data(
        #"{"type":"user","message":{"role":"user"}}"#.utf8
    )
    let claudeTool = Data(
        #"{"type":"assistant","message":{"stop_reason":"tool_use"}}"#.utf8
    )
    let claudeEnd = Data(
        #"{"type":"assistant","message":{"stop_reason":"end_turn"}}"#.utf8
    )
    expect(
        AgentActivityLineParser.updatedState(
            currentState: false,
            line: claudeUser,
            format: .claude
        ),
        "Claude 用户任务事件应标记为工作中"
    )
    expect(
        AgentActivityLineParser.updatedState(
            currentState: true,
            line: claudeTool,
            format: .claude
        ),
        "Claude tool_use 期间应继续工作"
    )
    expect(
        !AgentActivityLineParser.updatedState(
            currentState: true,
            line: claudeEnd,
            format: .claude
        ),
        "Claude end_turn 应标记为已结束"
    )
}

private func testSelectiveIntegrationSetup() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeSetupTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: root)
    }

    let codexDirectory = root.appendingPathComponent(
        ".codex",
        isDirectory: true
    )
    let sessionsDirectory = codexDirectory.appendingPathComponent(
        "sessions",
        isDirectory: true
    )
    try? fileManager.createDirectory(
        at: sessionsDirectory,
        withIntermediateDirectories: true
    )

    let configURL = codexDirectory.appendingPathComponent("hooks.json")
    let originalConfig: [String: Any] = [
        "description": "Existing user hooks",
        "hooks": [
            "UserPromptSubmit": [
                [
                    "hooks": [
                        [
                            "type": "command",
                            "command": "/usr/bin/true",
                            "timeout": 2
                        ]
                    ]
                ]
            ]
        ]
    ]
    if let data = try? JSONSerialization.data(
        withJSONObject: originalConfig,
        options: [.prettyPrinted, .sortedKeys]
    ) {
        try? data.write(to: configURL)
    }

    let helperURL = root.appendingPathComponent("AgentAwakeHook")
    try? Data("agentawake-test-helper".utf8).write(to: helperURL)
    try? fileManager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: helperURL.path
    )

    let manager = AgentIntegrationManager(
        homeDirectory: root,
        bundledHelperURL: helperURL
    )
    let initial = manager.inspect(.codex)
    expect(initial.state == .available, "检测到 Codex 后 Hooks 应保持可选")
    expect(initial.hasLocalActivityData, "应识别已有 Codex 活动目录")

    do {
        try manager.install(.codex)
    } catch {
        failures.append("Codex Hooks 安装失败：\(error.localizedDescription)")
    }

    expect(
        manager.inspect(.codex).state == .installed,
        "安装后 Codex Hooks 状态应为已安装"
    )
    expect(
        !fileManager.fileExists(
            atPath: root
                .appendingPathComponent(".claude/settings.json")
                .path
        ),
        "安装 Codex 集成时不应创建 Claude 配置"
    )
    expect(
        fileManager.fileExists(
            atPath: configURL.path + ".agentawake-backup"
        ),
        "首次修改已有配置前应创建备份"
    )

    let installedConfig = (try? String(contentsOf: configURL)) ?? ""
    expect(
        installedConfig.contains("usr") && installedConfig.contains("true"),
        "安装 Hooks 时必须保留用户原有命令"
    )
    expect(
        installedConfig.contains(AgentIntegrationManager.adapterID),
        "安装后配置应包含 AgentAwake 标识"
    )

    do {
        try manager.install(.codex)
        let repeatedConfig = (try? String(contentsOf: configURL)) ?? ""
        let adapterCount = repeatedConfig.components(
            separatedBy: AgentIntegrationManager.adapterID
        ).count - 1
        expect(adapterCount == 6, "重复安装不应追加重复的 Codex Hooks")
        try manager.uninstall(.codex)
    } catch {
        failures.append("Codex Hooks 更新或移除失败：\(error.localizedDescription)")
    }

    let uninstalledConfig = (try? String(contentsOf: configURL)) ?? ""
    expect(
        uninstalledConfig.contains("usr") && uninstalledConfig.contains("true"),
        "移除 Hooks 时必须保留用户原有命令"
    )
    expect(
        !uninstalledConfig.contains(AgentIntegrationManager.adapterID),
        "移除后不应残留 AgentAwake Hook"
    )
    expect(
        !fileManager.fileExists(atPath: manager.installedHelperURL.path),
        "没有集成使用 helper 时应移除稳定副本"
    )

    do {
        try manager.install(.claude)
        failures.append("未检测到 Claude 时不应创建配置")
    } catch {
        expect(
            manager.inspect(.claude).state == .notDetected,
            "未检测到 Claude 时状态应保持未检测到"
        )
    }

    let claudeDirectory = root.appendingPathComponent(
        ".claude",
        isDirectory: true
    )
    try? fileManager.createDirectory(
        at: claudeDirectory,
        withIntermediateDirectories: true
    )
    let invalidClaudeConfig = claudeDirectory.appendingPathComponent(
        "settings.json"
    )
    let invalidData = Data(#"{"hooks":"not-an-object"}"#.utf8)
    try? invalidData.write(to: invalidClaudeConfig)

    if case .invalidConfiguration = manager.inspect(.claude).state {
        expect(true, "异常 Claude 配置应被识别")
    } else {
        failures.append("异常 Claude 配置应显示配置错误")
    }

    do {
        try manager.install(.claude)
        failures.append("异常 Claude 配置不应被覆盖")
    } catch {
        expect(
            (try? Data(contentsOf: invalidClaudeConfig)) == invalidData,
            "安装失败后必须保持异常配置原文不变"
        )
        expect(
            !fileManager.fileExists(atPath: manager.installedHelperURL.path),
            "配置异常时不应留下未使用的 helper"
        )
    }
}

private func testBridgeSetupLifecycle() {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent(
            "AgentAwakeBridgeSetupTest-\(UUID().uuidString)",
            isDirectory: true
        )
    defer {
        try? fileManager.removeItem(at: root)
    }
    try? fileManager.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )

    let helperURL = root.appendingPathComponent("BundledAgentAwakeHook")
    try? Data("agentawake-bridge-helper".utf8).write(to: helperURL)
    try? fileManager.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: helperURL.path
    )
    let manager = AgentIntegrationManager(
        homeDirectory: root,
        bundledHelperURL: helperURL
    )

    expect(
        manager.inspectBridge().state == .available,
        "Bridge 初始状态应为可选"
    )
    do {
        try manager.installBridge()
        try manager.installBridge()
    } catch {
        failures.append("Bridge 安装或重复安装失败：\(error.localizedDescription)")
    }

    let installed = manager.inspectBridge()
    expect(installed.state == .installed, "Bridge 安装后应可用")
    expect(
        installed.commandTemplate.contains("--event EVENT"),
        "Bridge 应提供统一的一行事件模板"
    )
    expect(
        fileManager.isExecutableFile(atPath: installed.helperPath),
        "Bridge helper 应保持可执行"
    )
    expect(
        !fileManager.fileExists(
            atPath: manager.bridgeMarkerURL.path + ".agentawake-backup"
        ),
        "Bridge 自有状态文件不应产生冗余备份"
    )

    try? Data(#"{"enabled":"invalid"}"#.utf8).write(
        to: manager.bridgeMarkerURL,
        options: .atomic
    )
    expect(
        manager.inspectBridge().state == .needsRepair,
        "损坏的 Bridge 状态文件应显示需要修复"
    )
    do {
        try manager.installBridge()
    } catch {
        failures.append("Bridge 状态修复失败：\(error.localizedDescription)")
    }
    expect(
        manager.inspectBridge().state == .installed,
        "重新安装应修复 Bridge 状态文件"
    )

    let codexSessions = root
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("sessions", isDirectory: true)
    try? fileManager.createDirectory(
        at: codexSessions,
        withIntermediateDirectories: true
    )
    do {
        try manager.install(.codex)
    } catch {
        failures.append("Bridge 共存测试的 Codex Hooks 安装失败")
    }

    manager.uninstallBridge()
    expect(
        manager.inspectBridge().state == .available,
        "Bridge 移除后应回到可选状态"
    )
    expect(
        fileManager.fileExists(atPath: manager.installedHelperURL.path),
        "Hooks 仍在使用时，移除 Bridge 不应删除共享 helper"
    )
    do {
        try manager.uninstall(.codex)
    } catch {
        failures.append("Bridge 共存测试的 Codex Hooks 移除失败")
    }
    expect(
        !fileManager.fileExists(atPath: manager.installedHelperURL.path),
        "Bridge 与 Hooks 都移除后应清理共享 helper"
    )
}

testProtectionSession()
testExtensibleAgentIdentityAndEvents()
testCustomAdapterExtensionPoint()
testAgentActivityParsing()
testHookActivityStore()
testLegacyLeaseAndCustomBridge()
testHookOverridesTranscriptFallback()
testEventDrivenDetectorAndResourceBounds()
testSelectiveIntegrationSetup()
testBridgeSetupLifecycle()

if failures.isEmpty {
    let detector = SystemAgentDetector()
    let firstScanStartedAt = Date()
    let detected = detector.runningAgents()
    let firstScanDuration = Date().timeIntervalSince(firstScanStartedAt)
    let incrementalScanStartedAt = Date()
    let incrementalResult = detector.runningAgents()
    let incrementalScanDuration = Date().timeIntervalSince(
        incrementalScanStartedAt
    )
    let summary = detected.map {
        "\($0.kind.rawValue)(\($0.sessionID.suffix(8)))"
    }.joined(separator: ", ")

    expect(
        incrementalResult == detected,
        "没有新增日志时，增量检测结果应保持稳定"
    )

    if !failures.isEmpty {
        print("AgentAwake self-test: FAIL")
        failures.forEach { print("- \($0)") }
        exit(EXIT_FAILURE)
    }

    print("AgentAwake self-test: PASS")
    print("当前检测结果: \(summary.isEmpty ? "无 Agent 任务" : summary)")
    print(
        String(
            format: "首次扫描 %.0f ms，增量扫描 %.0f ms",
            firstScanDuration * 1_000,
            incrementalScanDuration * 1_000
        )
    )
    exit(EXIT_SUCCESS)
}

print("AgentAwake self-test: FAIL")
failures.forEach { print("- \($0)") }
exit(EXIT_FAILURE)
