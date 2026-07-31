import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var integrationSettingsController: IntegrationSettingsController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let appController = AppController()
        let integrationSettingsController = IntegrationSettingsController()
        let settingsWindowController = SettingsWindowController(
            settingsController: integrationSettingsController
        )
        self.appController = appController
        self.integrationSettingsController = integrationSettingsController
        self.settingsWindowController = settingsWindowController
        let statusItemController = StatusItemController(
            appController: appController,
            onOpenSettings: settingsWindowController.present
        )
        self.statusItemController = statusItemController

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasPresentedInitialPopover") {
            defaults.set(true, forKey: "hasPresentedInitialPopover")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                statusItemController.presentPopover()
            }
        }
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
