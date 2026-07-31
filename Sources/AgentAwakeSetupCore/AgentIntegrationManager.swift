import Foundation

public enum AgentIntegrationProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .claude:
            return "Claude"
        }
    }

    fileprivate var homeDirectoryName: String {
        ".\(rawValue)"
    }

    fileprivate var configurationFilename: String {
        switch self {
        case .codex:
            return "hooks.json"
        case .claude:
            return "settings.json"
        }
    }

    fileprivate var activityDirectoryComponents: [String] {
        switch self {
        case .codex:
            return ["sessions"]
        case .claude:
            return ["projects"]
        }
    }

    fileprivate var events: [String] {
        switch self {
        case .codex:
            return [
                "UserPromptSubmit",
                "PreToolUse",
                "PermissionRequest",
                "PostToolUse",
                "Stop",
                "SessionEnd"
            ]
        case .claude:
            return [
                "UserPromptSubmit",
                "PreToolUse",
                "PermissionRequest",
                "PostToolUse",
                "PostToolUseFailure",
                "Stop",
                "StopFailure",
                "SessionEnd"
            ]
        }
    }
}

public enum AgentIntegrationState: Equatable, Sendable {
    case notDetected
    case available
    case installed
    case needsRepair
    case invalidConfiguration(String)
}

public struct AgentIntegrationSnapshot: Identifiable, Equatable, Sendable {
    public let provider: AgentIntegrationProvider
    public let state: AgentIntegrationState
    public let hasLocalActivityData: Bool
    public let configurationPath: String

    public var id: String { provider.id }

    public init(
        provider: AgentIntegrationProvider,
        state: AgentIntegrationState,
        hasLocalActivityData: Bool,
        configurationPath: String
    ) {
        self.provider = provider
        self.state = state
        self.hasLocalActivityData = hasLocalActivityData
        self.configurationPath = configurationPath
    }
}

public enum AgentIntegrationError: LocalizedError {
    case providerNotDetected(String)
    case helperMissing(String)
    case invalidJSONObject(String)
    case invalidHooks(String)

    public var errorDescription: String? {
        switch self {
        case let .providerNotDetected(provider):
            return "尚未检测到 \(provider)，未创建新的配置目录。"
        case let .helperMissing(path):
            return "找不到 AgentAwakeHook：\(path)"
        case let .invalidJSONObject(path):
            return "配置不是有效的 JSON 对象，未修改：\(path)"
        case let .invalidHooks(path):
            return "配置中的 hooks 结构无法安全合并，未修改：\(path)"
        }
    }
}

public final class AgentIntegrationManager: @unchecked Sendable {
    public static let adapterID = "com.raymond.agentawake"

    public let homeDirectory: URL
    public let bundledHelperURL: URL

    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundledHelperURL: URL,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.bundledHelperURL = bundledHelperURL
        self.fileManager = fileManager
    }

    public var installedHelperURL: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("AgentAwake", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("AgentAwakeHook")
    }

    public func detectedProviders() -> [AgentIntegrationProvider] {
        AgentIntegrationProvider.allCases.filter(isDetected)
    }

    public func inspectAll() -> [AgentIntegrationSnapshot] {
        AgentIntegrationProvider.allCases.map(inspect)
    }

    public func inspect(
        _ provider: AgentIntegrationProvider
    ) -> AgentIntegrationSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return inspectUnlocked(provider)
    }

    public func install(_ provider: AgentIntegrationProvider) throws {
        lock.lock()
        defer { lock.unlock() }

        guard isDetected(provider) else {
            throw AgentIntegrationError.providerNotDetected(
                provider.displayName
            )
        }

        let configURL = configurationURL(for: provider)
        var root = try loadJSONObject(
            at: configURL,
            defaultValue: provider == .codex
                ? ["description": "Personal lifecycle hooks."]
                : [:]
        )
        try updateHooks(
            in: &root,
            provider: provider,
            handler: handler(
                for: provider,
                helperPath: installedHelperURL.path
            )
        )

        do {
            _ = try installStableHelper()
            try writeJSONObject(root, to: configURL)
        } catch {
            if !hasAnyConfiguredIntegrationUnlocked() {
                try? fileManager.removeItem(at: installedHelperURL)
            }
            throw error
        }
    }

    public func uninstall(_ provider: AgentIntegrationProvider) throws {
        lock.lock()
        defer { lock.unlock() }

        let configURL = configurationURL(for: provider)
        if fileManager.fileExists(atPath: configURL.path) {
            var root = try loadJSONObject(at: configURL, defaultValue: [:])
            let isConfigured = try hasAgentAwakeHandler(
                in: root,
                provider: provider,
                configPath: configURL.path
            )
            if isConfigured {
                try updateHooks(in: &root, provider: provider, handler: nil)
                try writeJSONObject(root, to: configURL)
            }
        }

        if !hasAnyConfiguredIntegrationUnlocked() {
            try? fileManager.removeItem(at: installedHelperURL)
        }
    }

    public func configurationURL(
        for provider: AgentIntegrationProvider
    ) -> URL {
        providerHomeURL(provider)
            .appendingPathComponent(provider.configurationFilename)
    }

    private func inspectUnlocked(
        _ provider: AgentIntegrationProvider
    ) -> AgentIntegrationSnapshot {
        let configURL = configurationURL(for: provider)
        let hasLocalActivityData = fileManager.fileExists(
            atPath: activityDirectoryURL(provider).path
        )

        guard isDetected(provider) else {
            return AgentIntegrationSnapshot(
                provider: provider,
                state: .notDetected,
                hasLocalActivityData: false,
                configurationPath: configURL.path
            )
        }

        guard fileManager.fileExists(atPath: configURL.path) else {
            return AgentIntegrationSnapshot(
                provider: provider,
                state: .available,
                hasLocalActivityData: hasLocalActivityData,
                configurationPath: configURL.path
            )
        }

        do {
            let root = try loadJSONObject(at: configURL, defaultValue: [:])
            let configured = try hasAgentAwakeHandler(
                in: root,
                provider: provider,
                configPath: configURL.path
            )
            guard configured else {
                return AgentIntegrationSnapshot(
                    provider: provider,
                    state: .available,
                    hasLocalActivityData: hasLocalActivityData,
                    configurationPath: configURL.path
                )
            }

            let helperIsCurrent = helperMatchesBundledVersion()
            return AgentIntegrationSnapshot(
                provider: provider,
                state: helperIsCurrent ? .installed : .needsRepair,
                hasLocalActivityData: hasLocalActivityData,
                configurationPath: configURL.path
            )
        } catch {
            return AgentIntegrationSnapshot(
                provider: provider,
                state: .invalidConfiguration(error.localizedDescription),
                hasLocalActivityData: hasLocalActivityData,
                configurationPath: configURL.path
            )
        }
    }

    private func isDetected(_ provider: AgentIntegrationProvider) -> Bool {
        fileManager.fileExists(atPath: providerHomeURL(provider).path)
    }

    private func providerHomeURL(
        _ provider: AgentIntegrationProvider
    ) -> URL {
        homeDirectory.appendingPathComponent(
            provider.homeDirectoryName,
            isDirectory: true
        )
    }

    private func activityDirectoryURL(
        _ provider: AgentIntegrationProvider
    ) -> URL {
        provider.activityDirectoryComponents.reduce(
            providerHomeURL(provider)
        ) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: true)
        }
    }

    private func helperMatchesBundledVersion() -> Bool {
        guard fileManager.isExecutableFile(atPath: installedHelperURL.path),
              let bundledData = try? Data(contentsOf: bundledHelperURL),
              let installedData = try? Data(contentsOf: installedHelperURL)
        else {
            return false
        }

        return bundledData == installedData
    }

    private func installStableHelper() throws -> URL {
        guard fileManager.isExecutableFile(atPath: bundledHelperURL.path) else {
            throw AgentIntegrationError.helperMissing(bundledHelperURL.path)
        }

        let destinationURL = installedHelperURL
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if bundledHelperURL.standardizedFileURL
            != destinationURL.standardizedFileURL
        {
            let data = try Data(contentsOf: bundledHelperURL)
            try data.write(to: destinationURL, options: .atomic)
        }

        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: destinationURL.path
        )
        return destinationURL
    }

    private func loadJSONObject(
        at url: URL,
        defaultValue: [String: Any]
    ) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue
        }

        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        else {
            throw AgentIntegrationError.invalidJSONObject(url.path)
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
            throw AgentIntegrationError.invalidHooks(configPath)
        }
        return groups
    }

    private func isAgentAwakeHandler(_ handler: [String: Any]) -> Bool {
        if let command = handler["command"] as? String,
           command.contains("--adapter-id \(Self.adapterID)")
        {
            return true
        }

        if let arguments = handler["args"] as? [String],
           let markerIndex = arguments.firstIndex(of: "--adapter-id"),
           arguments.indices.contains(markerIndex + 1),
           arguments[markerIndex + 1] == Self.adapterID
        {
            return true
        }

        return false
    }

    private func removingAgentAwakeHandlers(
        from groups: [[String: Any]],
        configPath: String
    ) throws -> [[String: Any]] {
        try groups.compactMap { originalGroup in
            var group = originalGroup
            guard let handlersValue = group["hooks"] else {
                return group
            }
            guard let handlers = handlersValue as? [[String: Any]] else {
                throw AgentIntegrationError.invalidHooks(configPath)
            }

            let retained = handlers.filter { !isAgentAwakeHandler($0) }
            guard !retained.isEmpty else {
                return nil
            }

            group["hooks"] = retained
            return group
        }
    }

    private func hasAgentAwakeHandler(
        in root: [String: Any],
        provider: AgentIntegrationProvider,
        configPath: String
    ) throws -> Bool {
        guard let hooksValue = root["hooks"] else {
            return false
        }
        guard let hooks = hooksValue as? [String: Any] else {
            throw AgentIntegrationError.invalidHooks(configPath)
        }

        for event in provider.events {
            let groups = try hookGroups(
                from: hooks[event],
                configPath: configPath
            )
            for group in groups {
                guard let handlersValue = group["hooks"] else {
                    continue
                }
                guard let handlers = handlersValue as? [[String: Any]] else {
                    throw AgentIntegrationError.invalidHooks(configPath)
                }
                if handlers.contains(where: isAgentAwakeHandler) {
                    return true
                }
            }
        }

        return false
    }

    private func updateHooks(
        in root: inout [String: Any],
        provider: AgentIntegrationProvider,
        handler: [String: Any]?
    ) throws {
        let configPath = configurationURL(for: provider).path
        let existingHooks = root["hooks"] as? [String: Any]
        if root["hooks"] != nil, existingHooks == nil {
            throw AgentIntegrationError.invalidHooks(configPath)
        }

        var hooks = existingHooks ?? [:]
        for event in provider.events {
            let groups = try hookGroups(
                from: hooks[event],
                configPath: configPath
            )
            var updated = try removingAgentAwakeHandlers(
                from: groups,
                configPath: configPath
            )

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
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        let backupURL = URL(fileURLWithPath: url.path + ".agentawake-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            return
        }
        try fileManager.copyItem(at: url, to: backupURL)
    }

    private func writeJSONObject(
        _ object: [String: Any],
        to url: URL
    ) throws {
        try fileManager.createDirectory(
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
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func handler(
        for provider: AgentIntegrationProvider,
        helperPath: String
    ) -> [String: Any] {
        switch provider {
        case .codex:
            let command = [
                singleQuotedShellArgument(helperPath),
                "--provider codex",
                "--adapter-id \(Self.adapterID)"
            ].joined(separator: " ")
            return [
                "type": "command",
                "command": command,
                "timeout": 3
            ]

        case .claude:
            return [
                "type": "command",
                "command": helperPath,
                "args": [
                    "--provider",
                    "claude",
                    "--adapter-id",
                    Self.adapterID
                ],
                "timeout": 3
            ]
        }
    }

    private func singleQuotedShellArgument(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func hasAnyConfiguredIntegrationUnlocked() -> Bool {
        AgentIntegrationProvider.allCases.contains { provider in
            let configURL = configurationURL(for: provider)
            guard fileManager.fileExists(atPath: configURL.path),
                  let root = try? loadJSONObject(
                    at: configURL,
                    defaultValue: [:]
                  )
            else {
                return false
            }
            return (try? hasAgentAwakeHandler(
                in: root,
                provider: provider,
                configPath: configURL.path
            )) == true
        }
    }
}
