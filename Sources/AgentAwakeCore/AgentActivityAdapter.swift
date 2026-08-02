import Foundation

public enum AgentActivityLogFormat: Sendable {
    case codex
    case claude
}

public enum AgentDetectionCapability: Hashable, Sendable {
    case automaticLocal
    case preciseHook
    case preciseBridge
}

public struct AgentActivityPattern: Sendable {
    public let data: Data
    public let isActive: Bool

    public init(data: Data, isActive: Bool) {
        self.data = data
        self.isActive = isActive
    }
}

public protocol AgentActivityAdapter: Sendable {
    var identity: AgentKind { get }
    var logRoots: [URL] { get }
    var watchRoots: [URL] { get }
    var capabilities: Set<AgentDetectionCapability> { get }
    var bootstrapPatterns: [AgentActivityPattern] { get }

    func updatedActivityState(
        currentState: Bool,
        line: Data
    ) -> Bool
    func sessionIdentifier(for activityURL: URL) -> String
}

public extension AgentActivityAdapter {
    func sessionIdentifier(for activityURL: URL) -> String {
        let filename = activityURL.deletingPathExtension().lastPathComponent
        guard filename.count >= 36 else {
            return filename
        }
        return String(filename.suffix(36))
    }
}

public struct LocalTranscriptAgentAdapter: AgentActivityAdapter {
    public let identity: AgentKind
    public let logFormat: AgentActivityLogFormat
    public let logRoots: [URL]
    public let watchRoots: [URL]
    public let capabilities: Set<AgentDetectionCapability>
    public let bootstrapPatterns: [AgentActivityPattern]

    public init(
        identity: AgentKind,
        logFormat: AgentActivityLogFormat,
        logRoots: [URL],
        watchRoots: [URL],
        capabilities: Set<AgentDetectionCapability>
            = [.automaticLocal]
    ) {
        self.identity = identity
        self.logFormat = logFormat
        self.logRoots = logRoots
        self.watchRoots = watchRoots
        self.capabilities = capabilities
        self.bootstrapPatterns = AgentActivityLineParser.bootstrapPatterns(
            for: logFormat
        )
    }

    public func updatedActivityState(
        currentState: Bool,
        line: Data
    ) -> Bool {
        AgentActivityLineParser.updatedState(
            currentState: currentState,
            line: line,
            patterns: bootstrapPatterns
        )
    }
}

public enum BuiltInAgentAdapters {
    public static func localTranscriptAdapters(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [any AgentActivityAdapter] {
        let codexHome = homeDirectory.appendingPathComponent(
            ".codex",
            isDirectory: true
        )
        let claudeHome = homeDirectory.appendingPathComponent(
            ".claude",
            isDirectory: true
        )
        let codexSessions = codexHome.appendingPathComponent(
            "sessions",
            isDirectory: true
        )
        let claudeProjects = claudeHome.appendingPathComponent(
            "projects",
            isDirectory: true
        )

        return [
            LocalTranscriptAgentAdapter(
                identity: .codex,
                logFormat: .codex,
                logRoots: [codexSessions],
                watchRoots: [codexSessions],
                capabilities: [.automaticLocal, .preciseHook]
            ),
            LocalTranscriptAgentAdapter(
                identity: .claude,
                logFormat: .claude,
                logRoots: [claudeProjects],
                watchRoots: [claudeProjects],
                capabilities: [.automaticLocal, .preciseHook]
            )
        ]
    }
}
