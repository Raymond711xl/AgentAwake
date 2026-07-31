import Foundation
import IOKit.pwr_mgt

public enum PowerAssertionError: LocalizedError {
    case creationFailed(type: String, code: IOReturn)

    public var errorDescription: String? {
        switch self {
        case let .creationFailed(type, code):
            return "无法创建 \(type) 临时断言（错误 \(code)）"
        }
    }
}

public final class PowerAssertionController {
    public private(set) var isHoldingAssertion = false

    private var assertionIDs: [IOPMAssertionID] = []
    private var idleCountdownAssertionID = IOPMAssertionID(
        kIOPMNullAssertionID
    )

    public init() {}

    deinit {
        release()
        cancelSystemIdleCountdown()
    }

    public func acquire(timeout: TimeInterval) throws {
        guard !isHoldingAssertion else {
            return
        }

        cancelSystemIdleCountdown()
        let boundedTimeout = max(1, timeout)

        do {
            let systemID = try createAssertion(
                type: kIOPMAssertionTypePreventUserIdleSystemSleep,
                name: "AgentAwake - Agent task",
                details: "Temporary system sleep assertion",
                timeout: boundedTimeout
            )
            assertionIDs.append(systemID)

            let displayID = try createAssertion(
                type: kIOPMAssertionTypePreventUserIdleDisplaySleep,
                name: "AgentAwake - Display awake",
                details: "Temporary display sleep assertion",
                timeout: boundedTimeout
            )
            assertionIDs.append(displayID)
            isHoldingAssertion = true
        } catch {
            release()
            throw error
        }
    }

    public func renew(timeout: TimeInterval) throws {
        release()
        try acquire(timeout: timeout)
    }

    public func release() {
        assertionIDs.forEach { assertionID in
            IOPMAssertionRelease(assertionID)
        }
        assertionIDs.removeAll(keepingCapacity: false)
        isHoldingAssertion = false
    }

    @discardableResult
    public func restartSystemIdleCountdown() -> Bool {
        let result = IOPMAssertionDeclareUserActivity(
            "AgentAwake - Agent finished" as CFString,
            kIOPMUserActiveLocal,
            &idleCountdownAssertionID
        )
        return result == kIOReturnSuccess
    }

    public func cancelSystemIdleCountdown() {
        guard idleCountdownAssertionID != IOPMAssertionID(
            kIOPMNullAssertionID
        ) else {
            return
        }

        IOPMAssertionRelease(idleCountdownAssertionID)
        idleCountdownAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
    }

    private func createAssertion(
        type: String,
        name: String,
        details: String,
        timeout: TimeInterval
    ) throws -> IOPMAssertionID {
        var assertionID = IOPMAssertionID()
        let result = IOPMAssertionCreateWithDescription(
            type as CFString,
            name as CFString,
            details as CFString,
            nil,
            nil,
            timeout,
            kIOPMAssertionTimeoutActionRelease as CFString,
            &assertionID
        )

        guard result == kIOReturnSuccess else {
            throw PowerAssertionError.creationFailed(
                type: type,
                code: result
            )
        }

        return assertionID
    }
}
