import AgentAwakeSetupCore
import Darwin
import Foundation

private enum SetupAction: String {
    case install
    case uninstall
    case status
}

private enum SetupCommandError: LocalizedError {
    case usage
    case invalidProvider(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            用法：AgentAwakeHookSetup install|uninstall|status \
            [--provider codex|claude] [--home 路径] \
            [--helper AgentAwakeHook路径]
            """
        case let .invalidProvider(value):
            return "不支持的 Agent：\(value)"
        }
    }
}

private func option(named name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1)
    else {
        return nil
    }
    return CommandLine.arguments[index + 1]
}

private func stateDescription(_ state: AgentIntegrationState) -> String {
    switch state {
    case .notDetected:
        return "未检测到"
    case .available:
        return "可选，尚未安装 Hooks"
    case .installed:
        return "Hooks 已安装"
    case .needsRepair:
        return "需要修复或更新"
    case let .invalidConfiguration(message):
        return "配置异常：\(message)"
    }
}

do {
    guard CommandLine.arguments.count >= 2,
          let action = SetupAction(rawValue: CommandLine.arguments[1])
    else {
        throw SetupCommandError.usage
    }

    let homeDirectory = option(named: "--home").map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser

    let executableURL = URL(
        fileURLWithPath: CommandLine.arguments[0]
    ).standardizedFileURL
    let helperURL = option(named: "--helper").map {
        URL(fileURLWithPath: $0)
    } ?? executableURL
        .deletingLastPathComponent()
        .appendingPathComponent("AgentAwakeHook")

    let manager = AgentIntegrationManager(
        homeDirectory: homeDirectory,
        bundledHelperURL: helperURL
    )

    let providers: [AgentIntegrationProvider]
    if let providerName = option(named: "--provider") {
        guard let provider = AgentIntegrationProvider(
            rawValue: providerName.lowercased()
        ) else {
            throw SetupCommandError.invalidProvider(providerName)
        }
        providers = [provider]
    } else {
        providers = manager.detectedProviders()
    }

    switch action {
    case .install:
        guard !providers.isEmpty else {
            print("未检测到 Codex 或 Claude；未创建任何配置。")
            exit(EXIT_SUCCESS)
        }
        for provider in providers {
            try manager.install(provider)
            print("\(provider.displayName) Hooks 已安装。")
        }
        if providers.contains(.codex) {
            print("Codex 还需在 /hooks 中审核并信任新增命令。")
        }

    case .uninstall:
        for provider in providers {
            try manager.uninstall(provider)
            print("\(provider.displayName) Hooks 已移除。")
        }

    case .status:
        let snapshots = manager.inspectAll().filter { snapshot in
            option(named: "--provider") == nil
                || providers.contains(snapshot.provider)
        }
        for snapshot in snapshots {
            print(
                "\(snapshot.provider.displayName)：" +
                stateDescription(snapshot.state)
            )
        }
    }
} catch {
    fputs("AgentAwake Hook Setup: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
