import AgentAwakeCore
import Combine
import Foundation

@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isProtecting = false
    @Published private(set) var selectedMode: ProtectionMode
    @Published private(set) var runningAgents: [RunningAgent] = []
    @Published private(set) var statusText = "已关闭 · 使用系统原设置"
    @Published private(set) var remainingText: String?

    var onStatusChange: (() -> Void)?

    private let detector: SystemAgentDetector
    private let powerController: PowerAssertionController
    private var session: ProtectionSession
    private var monitorTimer: Timer?
    private var scanTick = 0
    private var isScanning = false
    private var scanGeneration = 0
    private var idleStatusText = "已关闭 · 使用系统原设置"
    private var waitingStatusText = "已开启 · 等待 Agent"

    init(
        detector: SystemAgentDetector = SystemAgentDetector(),
        powerController: PowerAssertionController = PowerAssertionController()
    ) {
        self.detector = detector
        self.powerController = powerController
        self.selectedMode = .off
        self.session = ProtectionSession(mode: .off)
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
            refreshAgents()
        }
    }

    func shutdown() {
        stopMonitoring()
        powerController.release()
        powerController.cancelSystemIdleCountdown()
        _ = session.setEnabled(false, agentCount: 0, now: Date())
        selectedMode = .off
    }

    private func startMonitoring() {
        guard monitorTimer == nil else {
            return
        }

        scanTick = 0
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
        scanTick = 0
        isScanning = false
        scanGeneration += 1
    }

    private func handleTimerTick() {
        let now = Date()
        apply(session.tick(now: now), now: now)

        guard session.isEnabled else {
            return
        }

        if session.mode.isAgentMode {
            scanTick += 1
            if scanTick >= 4 {
                scanTick = 0
                refreshAgents()
            }
        }

        refreshPresentation(now: now)
    }

    private func refreshAgents() {
        guard session.isEnabled,
              session.mode.isAgentMode,
              !isScanning
        else {
            return
        }

        isScanning = true
        let generation = scanGeneration
        let detector = self.detector

        Task.detached(priority: .utility) {
            let agents = detector.runningAgents()

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
                self.runningAgents = agents
                let now = Date()
                self.apply(
                    self.session.updateAgentCount(
                        agents.count,
                        now: now
                    ),
                    now: now
                )
            }
        }
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

            case let .autoDisabled(reason):
                switch reason {
                case .durationElapsed:
                    idleStatusText = "时长已到 · 已归还休眠权限"
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
            let names = Array(Set(runningAgents.map(\.kind.rawValue))).sorted()
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
