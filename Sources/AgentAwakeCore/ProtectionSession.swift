import Foundation

public enum SessionEndReason: Equatable, Sendable {
    case durationElapsed
}

public enum SessionEffect: Equatable, Sendable {
    case acquire(timeout: TimeInterval)
    case renew(timeout: TimeInterval)
    case release
    case restartSystemIdleCountdown
    case agentFinished
    case autoDisabled(SessionEndReason)
}

public struct ProtectionSession: Sendable {
    public private(set) var isEnabled = false
    public private(set) var isProtecting = false
    public private(set) var hasSeenAgent = false
    public private(set) var deadline: Date?
    public private(set) var noAgentSince: Date?
    public private(set) var assertionRenewalAt: Date?

    public private(set) var mode: ProtectionMode
    public let agentEndGrace: TimeInterval
    public let agentAssertionLease: TimeInterval
    public let agentAssertionRenewalInterval: TimeInterval

    public init(
        mode: ProtectionMode = .off,
        agentEndGrace: TimeInterval = 5,
        agentAssertionLease: TimeInterval = 120,
        agentAssertionRenewalInterval: TimeInterval = 60
    ) {
        self.mode = mode
        self.agentEndGrace = agentEndGrace
        self.agentAssertionLease = agentAssertionLease
        self.agentAssertionRenewalInterval = agentAssertionRenewalInterval
    }

    public mutating func selectMode(_ mode: ProtectionMode) {
        guard !isEnabled else {
            return
        }

        self.mode = mode
    }

    public mutating func setEnabled(
        _ enabled: Bool,
        agentCount: Int,
        now: Date
    ) -> [SessionEffect] {
        if !enabled {
            return stop(autoReason: nil)
        }

        guard !mode.isOff else {
            return stop(autoReason: nil)
        }

        guard !isEnabled else {
            return updateAgentCount(agentCount, now: now)
        }

        isEnabled = true
        isProtecting = false
        hasSeenAgent = false
        deadline = nil
        noAgentSince = nil
        assertionRenewalAt = nil

        if let duration = mode.duration {
            isProtecting = true
            deadline = now.addingTimeInterval(duration)
            return [.acquire(timeout: duration)]
        }

        return updateAgentCount(agentCount, now: now)
    }

    public mutating func updateAgentCount(
        _ agentCount: Int,
        now: Date
    ) -> [SessionEffect] {
        guard isEnabled else {
            return []
        }

        guard !mode.isOff else {
            return stop(autoReason: nil)
        }

        guard mode.isAgentMode else {
            return tick(now: now)
        }

        if agentCount > 0 {
            noAgentSince = nil

            guard !isProtecting else {
                return []
            }

            hasSeenAgent = true
            isProtecting = true
            assertionRenewalAt = now.addingTimeInterval(
                agentAssertionRenewalInterval
            )
            return [.acquire(timeout: agentAssertionLease)]
        }

        guard hasSeenAgent else {
            return []
        }

        if noAgentSince == nil {
            noAgentSince = now
        }

        return tick(now: now)
    }

    public mutating func tick(now: Date) -> [SessionEffect] {
        guard isEnabled else {
            return []
        }

        if !mode.isAgentMode, let deadline, now >= deadline {
            return stop(autoReason: .durationElapsed)
        }

        if mode.isAgentMode {
            if let noAgentSince,
               now.timeIntervalSince(noAgentSince) >= agentEndGrace
            {
                return returnToAgentWaiting()
            }

            if noAgentSince == nil,
               isProtecting,
               let assertionRenewalAt,
               now >= assertionRenewalAt
            {
                self.assertionRenewalAt = now.addingTimeInterval(
                    agentAssertionRenewalInterval
                )
                return [.renew(timeout: agentAssertionLease)]
            }
        }

        return []
    }

    public func remainingTime(at now: Date) -> TimeInterval? {
        guard let deadline else {
            return nil
        }

        return max(0, deadline.timeIntervalSince(now))
    }

    private mutating func returnToAgentWaiting() -> [SessionEffect] {
        var effects: [SessionEffect] = []

        if isProtecting {
            effects.append(.release)
        }

        isProtecting = false
        hasSeenAgent = false
        deadline = nil
        noAgentSince = nil
        assertionRenewalAt = nil

        effects.append(.restartSystemIdleCountdown)
        effects.append(.agentFinished)
        return effects
    }

    private mutating func stop(
        autoReason: SessionEndReason?
    ) -> [SessionEffect] {
        var effects: [SessionEffect] = []

        if isProtecting {
            effects.append(.release)
        }

        isEnabled = false
        isProtecting = false
        hasSeenAgent = false
        deadline = nil
        noAgentSince = nil
        assertionRenewalAt = nil

        if let autoReason {
            effects.append(.autoDisabled(autoReason))
        }

        return effects
    }
}
