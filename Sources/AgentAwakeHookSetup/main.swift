import Darwin
import Foundation

private let adapterID = "com.raymond.agentawake"
private let codexEvents = [
    "UserPromptSubmit",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "Stop",
    "SessionEnd"
]
private let claudeEvents = [
    "UserPromptSubmit",
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PostToolUseFailure",
    "Stop",
    "StopFailure",
    "SessionEnd"
]

private enum SetupAction: String {
    case install
    case uninstall
}

private enum SetupError: LocalizedError {
    case usage
    case helperMissing(String)
    case invalidJSONObject(String)
    case invalidHooks(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return """
            用法：AgentAwakeHookSetup install|uninstall \
            [--home 路径] [--helper AgentAwakeHook路径]
            """
        case let .helperMissing(path):
            return "找不到 AgentAwakeHook：\(path)"
        case let .invalidJSONObject(path):
            return "配置不是有效的 JSON 对象，未修改：\(path)"
        case let .invalidHooks(path):
            return "配置中的 hooks 结构无法安全合并，未修改：\(path)"
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

private func loadJSONObject(
    at url: URL,
    defaultValue: [String: Any]
) throws -> [String: Any] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return defaultValue
    }

    let data = try Data(contentsOf: url)
    guard let object = try JSONSerialization.jsonObject(with: data)
        as? [String: Any]
    else {
        throw SetupError.invalidJSONObject(url.path)
    }

    return object
}

private func hookGroups(
    from value: Any?,
    configPath: String
) throws -> [[String: Any]] {
    guard let value else {
        return []
    }

    guard let groups = value as? [[String: Any]] else {
        throw SetupError.invalidHooks(configPath)
    }
    return groups
}

private func isAgentAwakeHandler(_ handler: [String: Any]) -> Bool {
    if let command = handler["command"] as? String,
       command.contains("--adapter-id \(adapterID)")
    {
        return true
    }

    if let arguments = handler["args"] as? [String],
       let markerIndex = arguments.firstIndex(of: "--adapter-id"),
       arguments.indices.contains(markerIndex + 1),
       arguments[markerIndex + 1] == adapterID
    {
        return true
    }

    return false
}

private func removingAgentAwakeHandlers(
    from groups: [[String: Any]]
) throws -> [[String: Any]] {
    try groups.compactMap { originalGroup in
        var group = originalGroup
        guard let handlersValue = group["hooks"] else {
            return group
        }
        guard let handlers = handlersValue as? [[String: Any]] else {
            throw SetupError.invalidHooks("hooks[].hooks")
        }

        let retained = handlers.filter { !isAgentAwakeHandler($0) }
        guard !retained.isEmpty else {
            return nil
        }

        group["hooks"] = retained
        return group
    }
}

private func singleQuotedShellArgument(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func codexHandler(helperPath: String) -> [String: Any] {
    let command = [
        singleQuotedShellArgument(helperPath),
        "--provider codex",
        "--adapter-id \(adapterID)"
    ].joined(separator: " ")

    return [
        "type": "command",
        "command": command,
        "timeout": 3
    ]
}

private func claudeHandler(helperPath: String) -> [String: Any] {
    [
        "type": "command",
        "command": helperPath,
        "args": [
            "--provider",
            "claude",
            "--adapter-id",
            adapterID
        ],
        "timeout": 3
    ]
}

private func updateHooks(
    in root: inout [String: Any],
    events: [String],
    handler: [String: Any]?,
    configPath: String
) throws {
    let existingHooks = root["hooks"] as? [String: Any]
    if root["hooks"] != nil, existingHooks == nil {
        throw SetupError.invalidHooks(configPath)
    }

    var hooks = existingHooks ?? [:]

    for event in events {
        let groups = try hookGroups(
            from: hooks[event],
            configPath: configPath
        )
        var updated = try removingAgentAwakeHandlers(from: groups)

        if let handler {
            updated.append(["hooks": [handler]])
        }

        if updated.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = updated
        }
    }

    root["hooks"] = hooks
}

private func createBackupIfNeeded(at url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return
    }

    let backupURL = URL(fileURLWithPath: url.path + ".agentawake-backup")
    guard !FileManager.default.fileExists(atPath: backupURL.path) else {
        return
    }

    try FileManager.default.copyItem(at: url, to: backupURL)
}

private func writeJSONObject(
    _ object: [String: Any],
    to url: URL
) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try createBackupIfNeeded(at: url)

    var data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
    try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
    )
}

private func installStableHelper(
    sourceURL: URL,
    homeDirectory: URL
) throws -> URL {
    guard FileManager.default.isExecutableFile(atPath: sourceURL.path) else {
        throw SetupError.helperMissing(sourceURL.path)
    }

    let destinationDirectory = homeDirectory
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("AgentAwake", isDirectory: true)
        .appendingPathComponent("bin", isDirectory: true)
    let destinationURL = destinationDirectory
        .appendingPathComponent("AgentAwakeHook")

    try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )

    if sourceURL.standardizedFileURL != destinationURL.standardizedFileURL {
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destinationURL, options: .atomic)
    }

    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: destinationURL.path
    )
    return destinationURL
}

private func configureCodex(
    action: SetupAction,
    helperPath: String?,
    homeDirectory: URL
) throws {
    let url = homeDirectory
        .appendingPathComponent(".codex", isDirectory: true)
        .appendingPathComponent("hooks.json")
    var root = try loadJSONObject(
        at: url,
        defaultValue: [
            "description": "Personal lifecycle hooks."
        ]
    )

    try updateHooks(
        in: &root,
        events: codexEvents,
        handler: helperPath.map(codexHandler),
        configPath: url.path
    )
    try writeJSONObject(root, to: url)
}

private func configureClaude(
    action: SetupAction,
    helperPath: String?,
    homeDirectory: URL
) throws {
    let url = homeDirectory
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("settings.json")
    var root = try loadJSONObject(at: url, defaultValue: [:])

    try updateHooks(
        in: &root,
        events: claudeEvents,
        handler: helperPath.map(claudeHandler),
        configPath: url.path
    )
    try writeJSONObject(root, to: url)
}

do {
    guard CommandLine.arguments.count >= 2,
          let action = SetupAction(rawValue: CommandLine.arguments[1])
    else {
        throw SetupError.usage
    }

    let homeDirectory = option(named: "--home").map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.homeDirectoryForCurrentUser

    let executableURL = URL(
        fileURLWithPath: CommandLine.arguments[0]
    ).standardizedFileURL
    let sourceHelperURL = option(named: "--helper").map {
        URL(fileURLWithPath: $0)
    } ?? executableURL
        .deletingLastPathComponent()
        .appendingPathComponent("AgentAwakeHook")

    let installedHelperURL: URL?
    switch action {
    case .install:
        installedHelperURL = try installStableHelper(
            sourceURL: sourceHelperURL,
            homeDirectory: homeDirectory
        )
    case .uninstall:
        installedHelperURL = nil
    }

    try configureCodex(
        action: action,
        helperPath: installedHelperURL?.path,
        homeDirectory: homeDirectory
    )
    try configureClaude(
        action: action,
        helperPath: installedHelperURL?.path,
        homeDirectory: homeDirectory
    )

    switch action {
    case .install:
        print("AgentAwake Hooks 已写入 Codex 与 Claude 配置。")
        print("Codex 还需在 /hooks 中审核并信任新增命令。")
    case .uninstall:
        print("AgentAwake Hooks 已从 Codex 与 Claude 配置移除。")
    }
} catch {
    fputs("AgentAwake Hook Setup: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
