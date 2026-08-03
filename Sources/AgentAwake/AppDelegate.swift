import AppKit
import AgentAwakeCore
import AgentAwakeSetupCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appController: AppController?
    private var integrationSettingsController: IntegrationSettingsController?
    private var settingsWindowController: SettingsWindowController?
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let qaHomePath = Self.argumentValue(after: "--qa-detector-home")
        let detector: SystemAgentDetector
        if let qaHomePath {
            detector = SystemAgentDetector(
                homeDirectory: URL(
                    fileURLWithPath: qaHomePath,
                    isDirectory: true
                )
            )
        } else {
            detector = SystemAgentDetector()
        }
        let appController = AppController(detector: detector)
        let integrationSettingsController: IntegrationSettingsController
        if let qaHomePath {
            let helperURL = Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("AgentAwakeHook")
            let manager = AgentIntegrationManager(
                homeDirectory: URL(
                    fileURLWithPath: qaHomePath,
                    isDirectory: true
                ),
                bundledHelperURL: helperURL
            )
            integrationSettingsController = IntegrationSettingsController(
                manager: manager
            )
        } else {
            integrationSettingsController = IntegrationSettingsController()
        }
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

        // Explicit command-line QA switches keep normal double-click launches
        // unchanged while allowing repeatable release-build resource/UI checks.
        if CommandLine.arguments.contains("--qa-agent-mode") {
            appController.setMode(.agent)
        }
        if CommandLine.arguments.contains("--qa-open-settings") {
            DispatchQueue.main.async {
                settingsWindowController.present()
            }
        }

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

    private static func argumentValue(after option: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: option),
              CommandLine.arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return CommandLine.arguments[index + 1]
    }
}
