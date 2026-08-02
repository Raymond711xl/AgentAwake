import AgentAwakeSetupCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: IntegrationSettingsController
    @AppStorage(CompletionSoundPlayer.preferenceKey)
    private var completionSoundEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                generalSection
                integrationSection
                bridgeSection

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
        .frame(width: 560, height: 650)
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

                Divider()

                HStack(spacing: 12) {
                    Toggle(
                        "结束时播放“星眠”",
                        isOn: $completionSoundEnabled
                    )

                    Spacer()

                    Button("试听") {
                        CompletionSoundPlayer.shared.playPreview()
                    }
                    .controlSize(.small)
                }

                Text(
                    "仅在倒计时自然结束，或最后一个 Agent 确认停止后播放；" +
                    "手动关闭和退出不会播放。"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var integrationSection: some View {
        settingsCard(title: "Agent 活动检测", systemImage: "puzzlepiece") {
            VStack(alignment: .leading, spacing: 14) {
                Text(
                    "自动检测无需配置；精确跟踪需要按 Agent 启用。" +
                    "Hooks 失效时会自动回退到本地活动记录。"
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

    private var bridgeSection: some View {
        settingsCard(title: "自定义 Agent Bridge", systemImage: "link") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("通用精确跟踪")
                        .font(.system(size: 13, weight: .medium))

                    Text(bridgeStatusText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(bridgeStatusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            bridgeStatusColor.opacity(0.1),
                            in: Capsule()
                        )

                    Spacer()
                    bridgeAction
                }

                Text(
                    "供支持运行命令的第三方 Agent 发送 start、heartbeat 和 " +
                    "stop。Bridge 每次写入事件后立即退出，不会增加常驻服务。"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if controller.bridge.state != .available {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(controller.bridge.commandTemplate)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 7)
                            )

                        Button("复制命令模板") {
                            controller.copyBridgeCommand()
                        }
                        .controlSize(.small)

                        Text(
                            "把 EVENT 替换为 start、heartbeat 或 stop；" +
                            "SESSION_ID 在同一次任务中保持一致。"
                        )
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bridgeAction: some View {
        switch controller.bridge.state {
        case .available:
            Button(controller.isChangingBridge ? "启用中…" : "启用 Bridge") {
                controller.installBridge()
            }
            .disabled(controller.isChangingBridge)

        case .installed:
            Button(controller.isChangingBridge ? "移除中…" : "移除") {
                controller.uninstallBridge()
            }
            .disabled(controller.isChangingBridge)

        case .needsRepair:
            Button(controller.isChangingBridge ? "修复中…" : "修复") {
                controller.installBridge()
            }
            .disabled(controller.isChangingBridge)
        }
    }

    private var bridgeStatusText: String {
        switch controller.bridge.state {
        case .available:
            return "可选"
        case .installed:
            return "已启用"
        case .needsRepair:
            return "需更新"
        }
    }

    private var bridgeStatusColor: Color {
        switch controller.bridge.state {
        case .available:
            return .secondary
        case .installed:
            return .green
        case .needsRepair:
            return .orange
        }
    }

    private func integrationRow(
        _ integration: AgentIntegrationSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

            if showsIntegrationPreview(integration.state) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("安装前预览 · 已有配置首次修改前会创建备份")
                        .foregroundStyle(.secondary)
                    Text("配置：\(integration.configurationPath)")
                    Text("新增：\(integration.commandPreview)")
                }
                .font(.system(size: 9.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(.leading, 38)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func showsIntegrationPreview(
        _ state: AgentIntegrationState
    ) -> Bool {
        switch state {
        case .available, .needsRepair:
            return true
        case .notDetected, .installed, .invalidConfiguration:
            return false
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
