import AgentAwakeCore
import Darwin
import Foundation

let controller = PowerAssertionController()
let holdSeconds = CommandLine.arguments
    .dropFirst()
    .first
    .flatMap(UInt32.init) ?? 5

do {
    try controller.acquire(timeout: 10)
    print("AgentAwake power probe: ACQUIRED")
    fflush(stdout)
    sleep(holdSeconds)
    controller.release()
    print("AgentAwake power probe: RELEASED")
    let restarted = controller.restartSystemIdleCountdown()
    print(
        restarted
            ? "AgentAwake power probe: IDLE COUNTDOWN RESTARTED"
            : "AgentAwake power probe: IDLE COUNTDOWN FAILED"
    )
    fflush(stdout)
    sleep(2)
    controller.cancelSystemIdleCountdown()
    exit(EXIT_SUCCESS)
} catch {
    print("AgentAwake power probe: FAIL - \(error.localizedDescription)")
    exit(EXIT_FAILURE)
}
