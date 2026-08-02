import AgentAwakeCore
import Darwin
import Foundation

private enum HookCommandError: LocalizedError {
    case usage
    case missingOption(String)
    case invalidProvider
    case invalidEvent(String)
    case invalidActivityEvent
    case inputTooLarge

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            用法：
              AgentAwakeHook --provider codex|claude
              AgentAwakeHook bridge --provider ID --session ID \
                --event start|heartbeat|stop [--display-name 名称] \
                [--activity-id ID] [--store-root 路径]
            """
        case let .missingOption(name):
            return "缺少参数：\(name)"
        case .invalidProvider:
            return "Agent ID 只能包含小写字母、数字、点、横线或下划线。"
        case let .invalidEvent(value):
            return "不支持的事件：\(value)"
        case .invalidActivityEvent:
            return "会话或活动标识无效。"
        case .inputTooLarge:
            return "Hook 输入超过 1 MiB，已拒绝处理。"
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

private func requiredOption(named name: String) throws -> String {
    guard let value = option(named: name), !value.isEmpty else {
        throw HookCommandError.missingOption(name)
    }
    return value
}

private func storeRoot() -> URL? {
    option(named: "--store-root").map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }
}

private func readHookInput() throws -> Data {
    let maximumBytes = 1_048_576
    let input = try FileHandle.standardInput.read(
        upToCount: maximumBytes + 1
    ) ?? Data()
    guard input.count <= maximumBytes else {
        throw HookCommandError.inputTooLarge
    }
    return input
}

private func runBridge() throws {
    let providerID = try requiredOption(named: "--provider")
    guard let provider = AgentKind(
        identifier: providerID,
        displayName: option(named: "--display-name")
    ) else {
        throw HookCommandError.invalidProvider
    }

    let eventValue = try requiredOption(named: "--event").lowercased()
    guard let eventKind = AgentActivityEventKind(rawValue: eventValue) else {
        throw HookCommandError.invalidEvent(eventValue)
    }
    guard let event = AgentActivityEvent(
        provider: provider,
        sessionID: try requiredOption(named: "--session"),
        activityID: option(named: "--activity-id"),
        kind: eventKind,
        source: .preciseBridge,
        eventName: "Bridge\(eventKind.rawValue.capitalized)"
    ) else {
        throw HookCommandError.invalidActivityEvent
    }

    let store = AgentHookActivityStore(
        rootDirectory: storeRoot()
            ?? AgentHookActivityStore.defaultRootDirectory()
    )
    _ = try store.handle(event: event)
}

private func runNativeHook() throws {
    let providerName = try requiredOption(named: "--provider")
    guard [AgentKind.codex, AgentKind.claude].contains(where: {
        $0.identifier == providerName.lowercased()
    }),
    let provider = AgentKind(identifier: providerName)
    else {
        throw HookCommandError.invalidProvider
    }

    let input: Data
    do {
        input = try readHookInput()
    } catch HookCommandError.inputTooLarge {
        // Tracking must never block the host Agent. Oversized payloads simply
        // fall back to automatic local detection.
        return
    }
    guard let decodedEvent = try? JSONDecoder().decode(
        AgentHookEvent.self,
        from: input
    ) else {
        return
    }
    let store = AgentHookActivityStore(
        rootDirectory: storeRoot()
            ?? AgentHookActivityStore.defaultRootDirectory()
    )
    _ = try? store.handle(provider: provider, input: input)

    if provider == .codex, decodedEvent.hookEventName == "Stop" {
        let response = Data(#"{"continue":true}"#.utf8)
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

do {
    if CommandLine.arguments.dropFirst().first == "bridge" {
        try runBridge()
    } else {
        try runNativeHook()
    }
    exit(EXIT_SUCCESS)
} catch {
    fputs("AgentAwake Hook: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
