import Foundation

public enum ProtectionMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case off = 0
    case thirtyMinutes = 1
    case oneHour = 2
    case twoHours = 3
    case agent = 4

    public var id: Int { rawValue }

    public var duration: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .thirtyMinutes:
            return 1_800
        case .oneHour:
            return 3_600
        case .twoHours:
            return 7_200
        case .agent:
            return nil
        }
    }

    public var isAgentMode: Bool {
        self == .agent
    }

    public var isOff: Bool {
        self == .off
    }

    public var title: String {
        switch self {
        case .off:
            return "未开启"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .twoHours:
            return "2 小时"
        case .agent:
            return "Agent"
        }
    }

    public var compactTitle: String {
        switch self {
        case .off:
            return "未开启"
        case .thirtyMinutes:
            return "30 分钟"
        case .oneHour:
            return "1 小时"
        case .twoHours:
            return "2 小时"
        case .agent:
            return "Agent"
        }
    }
}
