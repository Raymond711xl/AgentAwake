import AgentAwakeSetupCore
import Foundation
import ServiceManagement

@MainActor
final class IntegrationSettingsController: ObservableObject {
    @Published private(set) var integrations: [AgentIntegrationSnapshot] = []
    @Published private(set) var workingProvider: AgentIntegrationProvider?
    @Published private(set) var feedbackText: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    @Published private(set) var isChangingLaunchAtLogin = false

    private let manager: AgentIntegrationManager
    private let loginService: SMAppService

    init(
        manager: AgentIntegrationManager? = nil,
        loginService: SMAppService = .mainApp
    ) {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("AgentAwakeHook")
        self.manager = manager ?? AgentIntegrationManager(
            bundledHelperURL: helperURL
        )
        self.loginService = loginService
        refresh()
    }

    func refresh() {
        integrations = manager.inspectAll()
        launchAtLoginEnabled = loginService.status == .enabled
        launchAtLoginNeedsApproval = loginService.status == .requiresApproval
    }

    func install(_ provider: AgentIntegrationProvider) {
        guard workingProvider == nil else {
            return
        }

        workingProvider = provider
        feedbackText = nil
        do {
            try manager.install(provider)
            feedbackText = "\(provider.displayName) Hooks 已安装。"
        } catch {
            feedbackText = error.localizedDescription
        }
        workingProvider = nil
        refresh()
    }

    func uninstall(_ provider: AgentIntegrationProvider) {
        guard workingProvider == nil else {
            return
        }

        workingProvider = provider
        feedbackText = nil
        do {
            try manager.uninstall(provider)
            feedbackText = "\(provider.displayName) Hooks 已移除。"
        } catch {
            feedbackText = error.localizedDescription
        }
        workingProvider = nil
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isChangingLaunchAtLogin else {
            return
        }

        isChangingLaunchAtLogin = true
        feedbackText = nil

        Task { @MainActor in
            do {
                if enabled {
                    try loginService.register()
                } else {
                    try await loginService.unregister()
                }
            } catch {
                feedbackText = "无法更新登录项：\(error.localizedDescription)"
            }
            isChangingLaunchAtLogin = false
            refresh()
        }
    }
}
