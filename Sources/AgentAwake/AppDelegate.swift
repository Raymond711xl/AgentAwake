import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let appController = AppController()
        self.appController = appController
        statusItemController = StatusItemController(appController: appController)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appController?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}
