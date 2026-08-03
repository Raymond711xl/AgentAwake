import AgentAwakeSetupCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: IntegrationSettingsController
    @AppStorage(CompletionSoundPlayer.preferenceKey)
    private var completionSoundEnabled = true
    @State private var bridgeProviderID = "my-agent"
    @State private var bridgeDisplayName = "My Agent"

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
        settingsCard(title: "通用 Agent Bridge", systemImage: "link") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("把其他 Agent 的任务状态连接到 AgentAwake")
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
                    "适用于能在任务开始、运行中和结束时执行本地命令的 Agent。" +
                    "AgentAwake 只接收状态、Agent 名称和任务 ID，" +
                    "不读取提示词或回复内容。"
                )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                switch controller.bridge.state {
                case .available:
                    Text(
                        "启用后会安装一个用完即退出的本地 helper；" +
                        "不会替你修改第三方 Agent 的配置。"
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                case .installed:
                    bridgeConnectionGuide

                case .needsRepair:
                    Label(
                        "请先修复 Bridge，再复制接入命令。",
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var bridgeConnectionGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()

            HStack(alignment: .top, spacing: 10) {
                stepBadge(1)

                VStack(alignment: .leading, spacing: 9) {
                    Text("填写这个 Agent 的标识")
                        .font(.system(size: 12, weight: .medium))

                    HStack(alignment: .top, spacing: 10) {
                        bridgeIdentityField(
                            title: "Agent ID",
                            prompt: "my-agent",
                            help: "用于区分 Agent；会转为小写，可用字母、数字、.-_。",
                            text: $bridgeProviderID
                        )

                        bridgeIdentityField(
                            title: "显示名称",
                            prompt: "My Agent",
                            help: "任务运行时会在 AgentAwake 中显示。",
                            text: $bridgeDisplayName
                        )
                    }

                    if let bridgeCommandErrorText {
                        Label(
                            bridgeCommandErrorText,
                            systemImage: "exclamationmark.circle"
                        )
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                stepBadge(2)

                VStack(alignment: .leading, spacing: 10) {
                    Text("把命令分别放进对应的生命周期 Hook")
                        .font(.system(size: 12, weight: .medium))

                    Text(
                        "不要在终端依次执行这三条命令。" +
                        "请让你的 Agent 在对应时机自动调用。"
                    )
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(AgentBridgeLifecycleEvent.allCases) { event in
                        bridgeCommandRow(event)
                    }

                    Label(
                        "关键：把命令里的 $AGENT_SESSION_ID 换成 Agent 提供的" +
                        "任务 ID 变量，例如 task_id、session_id 或 conversation_id。" +
                        "如果 ID 来自 Hook 的 JSON 输入，请先在 Hook 脚本中读取它。" +
                        "同一次任务的三种事件必须使用同一个值。",
                        systemImage: "key"
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("复制全部示例") {
                            if let bridgeAllCommandsText {
                                controller.copyBridgeText(
                                    bridgeAllCommandsText,
                                    confirmation: "三条 Bridge 命令已复制。"
                                )
                            }
                        }
                        .controlSize(.small)
                        .disabled(bridgeCommandSet == nil)

                        Spacer()

                        Text("开始与结束必需；长任务需要心跳。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func stepBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(
                Color.primary.opacity(0.07),
                in: Circle()
            )
    }

    private func bridgeIdentityField(
        title: String,
        prompt: String,
        help: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))

            Text(help)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bridgeCommandRow(
        _ event: AgentBridgeLifecycleEvent
    ) -> some View {
        let command = bridgeCommandSet?.command(for: event)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: bridgeEventSymbol(event))
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 17)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bridgeEventTitle(event))
                        .font(.system(size: 11, weight: .medium))
                    Text(bridgeEventDescription(event))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("--event \(event.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button("复制") {
                    if let command {
                        controller.copyBridgeText(
                            command.text,
                            confirmation: "\(bridgeEventTitle(event))命令已复制。"
                        )
                    }
                }
                .controlSize(.small)
                .disabled(command == nil)
            }

            Text(command?.text ?? "填写有效的 Agent 信息后生成命令。")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .help(command?.text ?? "")
        }
        .padding(8)
        .background(
            Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private var bridgeCommandSet: AgentBridgeCommandSet? {
        try? AgentBridgeCommandSet(
            helperPath: controller.bridge.helperPath,
            providerID: bridgeProviderID,
            displayName: bridgeDisplayName
        )
    }

    private var bridgeCommandErrorText: String? {
        do {
            _ = try AgentBridgeCommandSet(
                helperPath: controller.bridge.helperPath,
                providerID: bridgeProviderID,
                displayName: bridgeDisplayName
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var bridgeAllCommandsText: String? {
        guard let bridgeCommandSet else {
            return nil
        }

        return bridgeCommandSet.commands.map { command in
            "# \(bridgeEventTitle(command.event))\n\(command.text)"
        }.joined(separator: "\n\n")
    }

    private func bridgeEventTitle(
        _ event: AgentBridgeLifecycleEvent
    ) -> String {
        switch event {
        case .start:
            return "任务开始"
        case .heartbeat:
            return "运行中（长任务）"
        case .stop:
            return "任务结束"
        }
    }

    private func bridgeEventDescription(
        _ event: AgentBridgeLifecycleEvent
    ) -> String {
        switch event {
        case .start:
            return "任务开始时调用，建立活动状态。"
        case .heartbeat:
            return "长任务定期调用；短任务可以省略。"
        case .stop:
            return "完成、取消或失败时调用，释放活动状态。"
        }
    }

    private func bridgeEventSymbol(
        _ event: AgentBridgeLifecycleEvent
    ) -> String {
        switch event {
        case .start:
            return "play.fill"
        case .heartbeat:
            return "waveform.path.ecg"
        case .stop:
            return "stop.fill"
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
