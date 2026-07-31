import AgentAwakeCore
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

testProtectionSession()
testAgentActivityParsing()
testHookActivityStore()
testHookOverridesTranscriptFallback()

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
