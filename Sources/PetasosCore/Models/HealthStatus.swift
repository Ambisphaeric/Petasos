import Foundation

public struct HealthStatus: Codable, Sendable, Equatable {
    public let status: String
    public let platform: String?

    public var isOK: Bool { status.lowercased() == "ok" }
}

public struct DetailedHealth: Codable, Sendable, Equatable {
    public let status: String
    public let platform: String?
    public let gatewayState: String?
    public let platforms: [String: PlatformHealth]?
    public let activeAgents: Int?
    public let pid: Int?

    public struct PlatformHealth: Codable, Sendable, Equatable {
        public let state: String
        public let errorCode: String?
        public let errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case state
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, platform, platforms, pid
        case gatewayState = "gateway_state"
        case activeAgents = "active_agents"
    }
}
