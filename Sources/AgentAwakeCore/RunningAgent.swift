import Foundation

public enum AgentKind: String, CaseIterable, Codable, Sendable {
    case codex = "Codex"
    case claude = "Claude"

    public init?(identifier: String) {
        switch identifier.lowercased() {
        case "codex":
            self = .codex
        case "claude":
            self = .claude
        default:
            return nil
        }
    }

    public var identifier: String {
        rawValue.lowercased()
    }
}

public enum AgentStatusSource: String, Codable, Sendable {
    case lifecycleHook
    case transcriptFallback
}

public struct RunningAgent: Identifiable, Equatable, Sendable {
    public let kind: AgentKind
    public let sessionID: String
    public let activityLogPath: String
    public let source: AgentStatusSource

    public var id: String {
        "\(kind.rawValue)-\(sessionID)"
    }

    public init(
        kind: AgentKind,
        sessionID: String,
        activityLogPath: String,
        source: AgentStatusSource = .transcriptFallback
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.activityLogPath = activityLogPath
        self.source = source
    }
}
