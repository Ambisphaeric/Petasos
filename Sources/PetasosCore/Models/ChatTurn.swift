import Foundation

public struct ChatTurn: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let role: Role
    public var text: String
    public let timestamp: Date

    public enum Role: String, Codable, Sendable {
        case user, assistant, system, tool
    }

    public init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = .init()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct Session: Codable, Sendable, Identifiable, Equatable {
    public let id: String          // hermes session id (X-Hermes-Session-Id)
    public var sessionKey: String? // X-Hermes-Session-Key
    public var title: String?
    public var turns: [ChatTurn]
    public var lastResponseID: String?
    public var conversationName: String?

    public init(id: String, sessionKey: String? = nil, title: String? = nil, turns: [ChatTurn] = [], lastResponseID: String? = nil, conversationName: String? = nil) {
        self.id = id
        self.sessionKey = sessionKey
        self.title = title
        self.turns = turns
        self.lastResponseID = lastResponseID
        self.conversationName = conversationName
    }
}
