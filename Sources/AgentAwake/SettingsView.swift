import AgentAwakeSetupCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: IntegrationSettingsController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                generalSection
                integrationSection

                if let feedbackText = controller.feedbackText {
                    Label(feedbackText, systemImage: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                footer
            }
            .padding(24)
        }
        .frame(width: 540, height: 520)
        .onAppear {
            controller.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("设置")
                .font(.system(size: 22, weight: .semibold))

            Text(
                "AgentAwake 下载后即可使用；" +
                "下面的项目都不是启动前置条件。"
            )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var generalSection: some View {
        settingsCard(title: "通用", systemImage: "gearshape") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(
                    "登录时启动 AgentAwake",
                    isOn: Binding(
                        get: { controller.launchAtLoginEnabled },
                        set: controller.setLaunchAtLogin
                    )
                )
                .disabled(controller.isChangingLaunchAtLogin)

                if controller.launchAtLoginNeedsApproval {
                    Text(
                        "macOS 正在等待你在“系统设置 → 登录项”中" +
                        "允许此项目。"
                    )
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else {
                    Text(
                        "App 每次启动仍会回到“未开启”，" +
                        "不会自动接管休眠。"
                    )
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var integrationSection: some View {
        settingsCard(title: "Agent 集成（可选）", systemImage: "puzzlepiece") {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "AgentAwake 不安装或运行大模型，只读取用户已经配置好的" +
                    "本机状态。安装 Hooks 只用于让开始和结束更及时，" +
                    "不安装也能使用。"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(controller.integrations) { integration in
                    integrationRow(integration)

                    if integration.id != controller.integrations.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func integrationRow(
        _ integration: AgentIntegrationSnapshot
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: providerSymbol(integration.provider))
                .font(.system(size: 16, weight: .medium))
                .frame(width: 26, height: 26)
                .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 7)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(integration.provider.displayName)
                        .font(.system(size: 13, weight: .medium))

                    statusBadge(integration.state)
                }

                Text(integrationDescription(integration))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)
            integrationActions(integration)
        }
    }

    @ViewBuilder
    private func integrationActions(
        _ integration: AgentIntegrationSnapshot
    ) -> some View {
        let isWorking = controller.workingProvider == integration.provider

        switch integration.state {
        case .notDetected:
            Button("未检测到") {}
                .disabled(true)

        case .available:
            Button(isWorking ? "安装中…" : "安装 Hooks") {
                controller.install(integration.provider)
            }
            .disabled(controller.workingProvider != nil)

        case .installed:
            Button(isWorking ? "移除中…" : "移除") {
                controller.uninstall(integration.provider)
            }
            .disabled(controller.workingProvider != nil)

        case .needsRepair:
            Button(isWorking ? "修复中…" : "修复") {
                controller.install(integration.provider)
            }
            .disabled(controller.workingProvider != nil)

        case .invalidConfiguration:
            Button("需手动检查") {}
                .disabled(true)
        }
    }

    private func statusBadge(
        _ state: AgentIntegrationState
    ) -> some View {
        Text(statusText(state))
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(statusColor(state))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                statusColor(state).opacity(0.1),
                in: Capsule()
            )
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var footer: some View {
        HStack {
            Label("完全本地运行 · 无账号 · 无云服务", systemImage: "lock")
            Spacer()
            Text(versionText)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "开发版"
        return "AgentAwake \(version)"
    }

    private func providerSymbol(
        _ provider: AgentIntegrationProvider
    ) -> String {
        switch provider {
        case .codex:
            return "terminal"
        case .claude:
            return "text.bubble"
        }
    }

    private func statusText(_ state: AgentIntegrationState) -> String {
        switch state {
        case .notDetected:
            return "未检测到"
        case .available:
            return "可选"
        case .installed:
            return "已安装"
        case .needsRepair:
            return "需更新"
        case .invalidConfiguration:
            return "配置异常"
        }
    }

    private func statusColor(_ state: AgentIntegrationState) -> Color {
        switch state {
        case .installed:
            return .green
        case .needsRepair, .invalidConfiguration:
            return .orange
        case .notDetected, .available:
            return .secondary
        }
    }

    private func integrationDescription(
        _ integration: AgentIntegrationSnapshot
    ) -> String {
        switch integration.state {
        case .notDetected:
            return "不会创建 \(integration.provider.displayName) 配置。"
        case .available where integration.hasLocalActivityData:
            return "已发现本地活动记录；当前可直接使用日志检测。"
        case .available:
            return "已检测到应用；Hooks 尚未安装。"
        case .installed where integration.provider == .codex:
            return "Hook 已配置；Codex 首次使用时仍需在 /hooks 中确认信任。"
        case .installed:
            return "Hook 已配置，状态变化会更及时。"
        case .needsRepair:
            return "已安装的 helper 与当前 App 版本不一致。"
        case let .invalidConfiguration(message):
            return message
        }
    }
}
