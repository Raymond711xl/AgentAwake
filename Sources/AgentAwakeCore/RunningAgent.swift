import Foundation

public struct AgentKind: Hashable, Codable, Sendable {
    public static let codex = AgentKind(
        uncheckedIdentifier: "codex",
        displayName: "Codex"
    )
    public static let claude = AgentKind(
        uncheckedIdentifier: "claude",
        displayName: "Claude"
    )
    public static let allCases: [AgentKind] = [.codex, .claude]

    public let identifier: String
    public let displayName: String

    public var rawValue: String { displayName }

    public static func == (lhs: AgentKind, rhs: AgentKind) -> Bool {
        lhs.identifier == rhs.identifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }

    public init?(identifier: String, displayName: String? = nil) {
        let normalizedIdentifier = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard Self.isValidIdentifier(normalizedIdentifier) else {
            return nil
        }

        let resolvedDisplayName: String
        switch normalizedIdentifier {
        case Self.codex.identifier:
            resolvedDisplayName = displayName ?? Self.codex.displayName
        case Self.claude.identifier:
            resolvedDisplayName = displayName ?? Self.claude.displayName
        default:
            resolvedDisplayName = displayName ?? normalizedIdentifier
        }

        let trimmedDisplayName = resolvedDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidDisplayName(trimmedDisplayName) else {
            return nil
        }

        self.identifier = normalizedIdentifier
        self.displayName = trimmedDisplayName
    }

    private init(
        uncheckedIdentifier: String,
        displayName: String
    ) {
        self.identifier = uncheckedIdentifier
        self.displayName = displayName
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case displayName
    }

    public init(from decoder: Decoder) throws {
        if let legacyValue = try? decoder.singleValueContainer()
            .decode(String.self)
        {
            let knownKind: AgentKind?
            switch legacyValue.lowercased() {
            case "codex":
                knownKind = .codex
            case "claude":
                knownKind = .claude
            default:
                knownKind = AgentKind(identifier: legacyValue)
            }

            guard let knownKind else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Invalid legacy Agent identifier."
                    )
                )
            }
            self = knownKind
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(
            String.self,
            forKey: .identifier
        )
        let displayName = try container.decodeIfPresent(
            String.self,
            forKey: .displayName
        )
        guard let kind = AgentKind(
            identifier: identifier,
            displayName: displayName
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: container,
                debugDescription: "Invalid Agent identifier or display name."
            )
        }
        self = kind
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(displayName, forKey: .displayName)
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.count <= 64,
              value.first?.isASCII == true,
              value.first?.isLetter == true || value.first?.isNumber == true
        else {
            return false
        }

        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...122:
                return true
            default:
                return scalar == "-" || scalar == "_" || scalar == "."
            }
        }
    }

    private static func isValidDisplayName(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64 else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }
}

public enum AgentConfidence: String, Codable, Sendable {
    case automatic
    case precise
}

public enum AgentStatusSource: String, Codable, Sendable {
    case automaticLocal
    case preciseHook
    case preciseBridge

    public static var transcriptFallback: AgentStatusSource {
        .automaticLocal
    }

    public static var lifecycleHook: AgentStatusSource {
        .preciseHook
    }

    public var confidence: AgentConfidence {
        switch self {
        case .automaticLocal:
            return .automatic
        case .preciseHook, .preciseBridge:
            return .precise
        }
    }
}

public enum AgentActivityEventKind: String, Codable, Sendable {
    case start
    case heartbeat
    case stop
}

public struct AgentActivityEvent: Equatable, Sendable {
    public let schemaVersion: Int
    public let provider: AgentKind
    public let sessionID: String
    public let activityID: String?
    public let kind: AgentActivityEventKind
    public let source: AgentStatusSource
    public let eventName: String
    public let occurredAt: Date

    public init?(
        schemaVersion: Int = 1,
        provider: AgentKind,
        sessionID: String,
        activityID: String? = nil,
        kind: AgentActivityEventKind,
        source: AgentStatusSource,
        eventName: String? = nil,
        occurredAt: Date = Date()
    ) {
        let normalizedSessionID = sessionID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard schemaVersion == 1,
              !normalizedSessionID.isEmpty,
              normalizedSessionID.count <= 256,
              !normalizedSessionID.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            return nil
        }

        let normalizedActivityID = activityID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedActivityID,
           (
               normalizedActivityID.count > 256
                   || normalizedActivityID.unicodeScalars.contains(where: {
                       CharacterSet.controlCharacters.contains($0)
                   })
           )
        {
            return nil
        }

        let normalizedEventName = (eventName ?? kind.rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEventName.isEmpty,
              normalizedEventName.count <= 64,
              !normalizedEventName.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              })
        else {
            return nil
        }

        self.schemaVersion = schemaVersion
        self.provider = provider
        self.sessionID = normalizedSessionID
        self.activityID = normalizedActivityID?.isEmpty == false
            ? normalizedActivityID
            : nil
        self.kind = kind
        self.source = source
        self.eventName = normalizedEventName
        self.occurredAt = occurredAt
    }
}

public struct RunningAgent: Identifiable, Equatable, Sendable {
    public let kind: AgentKind
    public let sessionID: String
    public let activityLogPath: String
    public let source: AgentStatusSource

    public var id: String {
        "\(kind.identifier.count):\(kind.identifier):\(sessionID)"
    }

    public var confidence: AgentConfidence {
        source.confidence
    }

    public init(
        kind: AgentKind,
        sessionID: String,
        activityLogPath: String,
        source: AgentStatusSource = .automaticLocal
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.activityLogPath = activityLogPath
        self.source = source
    }
}
