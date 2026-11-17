import AgentAwakeCore
import AppKit
import ApplicationServices
import Combine
import Foundation
import OSLog

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isProtecting = false
    @Published private(set) var selectedMode: ProtectionMode
    @Published private(set) var runningAgents: [RunningAgent] = []
    @Published private(set) var statusText = "已关闭 · 使用系统原设置"
    @Published private(set) var remainingText: String?
    @Published private(set) var chatDetectionEnabled: Bool
    @Published private(set) var chatState: ChatGPTChatDetector.State = .noComposer

    var onStatusChange: (() -> Void)?

    private let detector: SystemAgentDetector
    private let chatDetector = ChatGPTChatDetector()
    private let powerController: PowerAssertionController
    private let completionSoundPlayer: CompletionSoundPlayer
    private var session: ProtectionSession
    private var monitorTimer: Timer?
    private var nextReconciliationAt: TimeInterval = 0
    private var isScanning = false
    private var pendingAgentRefresh = false
    private var pendingFullReconciliation = false
    private var scanGeneration = 0
    private var chatScanGeneration = 0
    private var isScanningChat = false
    private var localAgents: [RunningAgent] = []
    private var idleStatusText = "已关闭 · 使用系统原设置"
    private var waitingStatusText = "已开启 · 等待 Agent"

    private static let chatPreferenceKey = "chatGPTChatDetectionEnabled"
    private static let chatLogger = Logger(
        subsystem: "com.raymond.agentawake", category: "ChatDetection"
    )
    private static let chatAgent = RunningAgent(
        kind: .chatGPT, sessionID: "desktop-chat", activityLogPath: "",
        source: .accessibility, surface: .chatGPTChat
    )

    init(
        detector: SystemAgentDetector = SystemAgentDetector(),
        powerController: PowerAssertionController = PowerAssertionController(),
        completionSoundPlayer: CompletionSoundPlayer? = nil
    ) {
        self.detector = detector
        self.powerController = powerController
        self.completionSoundPlayer = completionSoundPlayer ?? .shared
        self.selectedMode = .off
        self.session = ProtectionSession(mode: .off)
        self.chatDetectionEnabled = UserDefaults.standard.bool(forKey: Self.chatPreferenceKey)
        if chatDetectionEnabled, !AXIsProcessTrusted() {
            chatState = .permissionRequired
        }
    }

    func setMode(_ mode: ProtectionMode) {
        guard mode != selectedMode else {
            return
        }

        let now = Date()
        deactivateCurrentMode(now: now)

        selectedMode = mode
        session.selectMode(mode)

        guard !mode.isOff else {
            idleStatusText = "已关闭 · 已归还休眠权限"
            refreshPresentation(now: now)
            return
        }

        idleStatusText = "已关闭 · 使用系统原设置"
        waitingStatusText = "已开启 · 等待 Agent"
        apply(
            session.setEnabled(true, agentCount: 0, now: now),
            now: now
        )

        guard session.isEnabled else {
            return
        }

        startMonitoring()
        if mode.isAgentMode {
            startAgentEventMonitoring()
            refreshAgents(forceReconciliation: true)
            refreshChat()
        }
    }

    func shutdown() {
        stopMonitoring()
        powerController.release()
        powerController.cancelSystemIdleCountdown()
        _ = session.setEnabled(false, agentCount: 0, now: Date())
        selectedMode = .off
    }

    func setChatDetectionEnabled(_ enabled: Bool) {
        guard enabled != chatDetectionEnabled else { return }
        chatDetectionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.chatPreferenceKey)
        chatScanGeneration += 1
        updateChatState(enabled && !AXIsProcessTrusted() ? .permissionRequired : .noComposer)
        refreshChat()
    }

    func openChatAccessibilitySettings() {
        guard chatDetectionEnabled else { return }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
            updateChatState(.permissionRequired)
            if let settings = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) {
                NSWorkspace.shared.open(settings)
            }
        }
    }

    func refreshChatPermissionStatus() {
        guard chatDetectionEnabled else { return }
        if !AXIsProcessTrusted() {
            updateChatState(.permissionRequired)
        } else if chatState == .permissionRequired {
            updateChatState(.noComposer)
        }
        refreshChat()
    }

    private func startMonitoring() {
        guard monitorTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTimerTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        detector.stopMonitoring()
        nextReconciliationAt = 0
        isScanning = false
        pendingAgentRefresh = false
        pendingFullReconciliation = false
        scanGeneration += 1
        chatScanGeneration += 1
        localAgents = []
        chatState = chatDetectionEnabled && !AXIsProcessTrusted()
            ? .permissionRequired : .noComposer
    }

    private func handleTimerTick() {
        let now = Date()
        apply(session.tick(now: now), now: now)

        guard session.isEnabled else {
            return
        }

        if session.mode.isAgentMode {
            if !isScanning,
               ProcessInfo.processInfo.systemUptime >= nextReconciliationAt
            {
                refreshAgents(checkForMissedEvents: true)
            }
            refreshChat()
        }

        refreshPresentation(now: now)
    }

    private func startAgentEventMonitoring() {
        detector.startMonitoring { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAgents()
            }
        }
    }

    private func refreshAgents(
        forceReconciliation: Bool = false,
        checkForMissedEvents: Bool = false
    ) {
        guard session.isEnabled,
              session.mode.isAgentMode
        else {
            return
        }

        guard !isScanning else {
            pendingAgentRefresh = true
            pendingFullReconciliation = pendingFullReconciliation
                || forceReconciliation
            return
        }

        isScanning = true
        let generation = scanGeneration
        let detector = self.detector

        Task.detached(priority: .utility) {
            let scanStartedAt = ProcessInfo.processInfo.systemUptime
            let agents = detector.runningAgents(
                forceReconciliation: forceReconciliation,
                checkForMissedEvents: checkForMissedEvents
            )
            let scanFinishedAt = ProcessInfo.processInfo.systemUptime

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }

                guard self.scanGeneration == generation,
                      self.session.isEnabled,
                      self.session.mode.isAgentMode
                else {
                    return
                }

                self.isScanning = false
                if forceReconciliation || checkForMissedEvents {
                    // A successful file-event subscription can still miss
                    // appends. Back off when checking a large session history.
                    let scanDuration = scanFinishedAt - scanStartedAt
                    let interval = min(60, max(5, scanDuration * 200))
                    self.nextReconciliationAt = scanFinishedAt + interval
                }
                self.localAgents = agents
                self.applyAgentActivity(now: Date())

                let shouldRefreshAgain = self.pendingAgentRefresh
                let shouldReconcile = self.pendingFullReconciliation
                self.pendingAgentRefresh = false
                self.pendingFullReconciliation = false
                if shouldRefreshAgain {
                    self.refreshAgents(
                        forceReconciliation: shouldReconcile
                    )
                }
            }
        }
    }

    private func refreshChat() {
        guard session.isEnabled, session.mode.isAgentMode,
              chatDetectionEnabled, !isScanningChat else { return }

        isScanningChat = true
        let generation = chatScanGeneration
        let detector = chatDetector
        let processIDs = NSRunningApplication.runningApplications(
            withBundleIdentifier: ChatGPTChatDetector.bundleIdentifier
        ).map(\.processIdentifier)

        Task.detached(priority: .utility) { [weak self] in
            let state = detector.state(for: processIDs)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isScanningChat = false
                guard self.chatScanGeneration == generation else { return }
                self.updateChatState(state)
            }
        }
    }

    private func updateChatState(_ state: ChatGPTChatDetector.State) {
        guard state != chatState else { return }
        let wasGenerating = chatState == .generating
        chatState = state
        if state == .generating {
            Self.chatLogger.info("Chat composer detected generating")
        } else if wasGenerating {
            Self.chatLogger.info("Chat generating control disappeared")
        }
        if session.isEnabled, session.mode.isAgentMode {
            applyAgentActivity(now: Date(), confirmedFinish: wasGenerating && state == .idle)
        }
    }

    private func applyAgentActivity(now: Date, confirmedFinish: Bool = false) {
        var agents = localAgents
        if chatState == .generating {
            agents.append(Self.chatAgent)
        }
        if runningAgents != agents {
            runningAgents = agents
        }
        apply(
            session.updateAgentCount(agents.count, now: now, confirmedFinish: confirmedFinish),
            now: now
        )
    }

    private func apply(_ effects: [SessionEffect], now: Date) {
        var acquisitionError: Error?

        for effect in effects {
            switch effect {
            case let .acquire(timeout):
                do {
                    try powerController.acquire(timeout: timeout)
                } catch {
                    acquisitionError = error
                }

            case let .renew(timeout):
                do {
                    try powerController.renew(timeout: timeout)
                } catch {
                    acquisitionError = error
                }

            case .release:
                powerController.release()

            case .restartSystemIdleCountdown:
                _ = powerController.restartSystemIdleCountdown()

            case .agentFinished:
                waitingStatusText = "Agent 已结束 · 已恢复系统休眠计时"
                completionSoundPlayer.playCompletionIfEnabled()

            case let .autoDisabled(reason):
                switch reason {
                case .durationElapsed:
                    idleStatusText = "时长已到 · 已归还休眠权限"
                    completionSoundPlayer.playCompletionIfEnabled()
                }
                selectedMode = .off
                session.selectMode(.off)
            }
        }

        if let acquisitionError {
            powerController.release()
            _ = session.setEnabled(false, agentCount: 0, now: now)
            selectedMode = .off
            session.selectMode(.off)
            idleStatusText = acquisitionError.localizedDescription
        }

        if !session.isEnabled {
            runningAgents = []
            stopMonitoring()
        }

        refreshPresentation(now: now)
    }

    private func refreshPresentation(now: Date) {
        let wasEnabled = isEnabled
        let wasProtecting = isProtecting
        isEnabled = session.isEnabled
        isProtecting = session.isProtecting
            && powerController.isHoldingAssertion

        if isProtecting,
           session.mode.isAgentMode,
           session.noAgentSince != nil
        {
            statusText = "确认 Agent 是否结束…"
        } else if isProtecting, session.mode.isAgentMode {
            let names = Set(runningAgents.map(\.displayName)).sorted()
            statusText = "\(names.joined(separator: "、")) 工作中 · 临时接管休眠"
        } else if isProtecting {
            statusText = "定时防休眠 · 倒计时中"
        } else if isEnabled {
            statusText = waitingStatusText
        } else {
            statusText = idleStatusText
        }

        if let remaining = session.remainingTime(at: now), isProtecting {
            remainingText = formatRemainingTime(remaining)
        } else {
            remainingText = nil
        }

        if wasEnabled != isEnabled || wasProtecting != isProtecting {
            onStatusChange?()
        }
    }

    private func formatRemainingTime(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.up)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func deactivateCurrentMode(now: Date) {
        apply(
            session.setEnabled(false, agentCount: 0, now: now),
            now: now
        )
        powerController.release()
        runningAgents = []
        stopMonitoring()
    }
}
