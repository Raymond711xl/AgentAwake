import AgentAwakeCore
import AppKit
import SwiftUI

struct StatusPopoverView: View {
    @ObservedObject var appController: AppController
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                Text("防休眠")
                    .font(.system(size: 13, weight: .semibold))

                ProtectionModeSlider(
                    selection: appController.selectedMode,
                    onSelect: appController.setMode
                )

                HStack(spacing: 0) {
                    ForEach(ProtectionMode.allCases) { mode in
                        modeLabel(mode)
                            .frame(
                                maxWidth: .infinity,
                                alignment: labelAlignment(for: mode)
                            )
                    }
                }

                Text(modeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            sessionDetails

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 11) {
            SleepStatusMark(isActive: appController.isEnabled)

            VStack(alignment: .leading, spacing: 3) {
                Text("AgentAwake")
                    .font(.system(size: 15, weight: .semibold))

                Text(appController.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let remainingText = appController.remainingText {
                Text(remainingText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sessionDetails: some View {
        if appController.isProtecting {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)

                Text(protectionSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        } else if appController.isEnabled {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text("等待 Codex 或 Claude 任务")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("不修改系统原设置", systemImage: "checkmark.shield")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            Button("设置") {
                onOpenSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    private var agentSummary: String {
        guard !appController.runningAgents.isEmpty else {
            return "确认 Agent 状态…"
        }

        let grouped = Dictionary(grouping: appController.runningAgents, by: \.kind)
        return grouped.keys
            .sorted { $0.rawValue < $1.rawValue }
            .map { kind in
                let count = grouped[kind]?.count ?? 0
                return count > 1 ? "\(kind.rawValue) × \(count)" : kind.rawValue
            }
            .joined(separator: " · ")
    }

    private var protectionSummary: String {
        if appController.selectedMode.isAgentMode {
            return agentSummary
        }

        return "\(appController.selectedMode.title) · 定时保护"
    }

    private var modeDescription: String {
        if appController.selectedMode.isOff {
            return "滑到任一模式即可启用；返回这里会立即释放休眠权限。"
        }

        if appController.selectedMode.isAgentMode {
            return "仅在 Agent 工作时接管，结束后恢复系统休眠计时。"
        }

        return "已立即保持唤醒，并按所选时长倒计时。"
    }

    private func modeLabel(_ mode: ProtectionMode) -> some View {
        Text(mode.compactTitle)
            .font(
                .system(
                    size: 10,
                    weight: appController.selectedMode == mode
                        ? .semibold
                        : .regular
                )
            )
            .foregroundStyle(
                appController.selectedMode == mode
                    ? Color.primary
                    : Color.secondary
            )
    }

    private func labelAlignment(for mode: ProtectionMode) -> Alignment {
        switch mode {
        case .off:
            return .leading
        case .agent:
            return .trailing
        default:
            return .center
        }
    }
}
