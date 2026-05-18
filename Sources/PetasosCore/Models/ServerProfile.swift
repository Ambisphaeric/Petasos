import Foundation

/// Saved server connection (URL + Keychain-stored bearer reference + last-known capabilities).
public struct ServerProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var nickname: String
    public var baseURL: URL
    public var keychainAccount: String   // identifier the Keychain entry is filed under
    public var preferredModel: String?
    public var lastCapabilities: Capabilities?
    public var lastVerifiedAt: Date?

    public init(
        id: UUID = UUID(),
        nickname: String,
        baseURL: URL,
        keychainAccount: String,
        preferredModel: String? = nil,
        lastCapabilities: Capabilities? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.baseURL = baseURL
        self.keychainAccount = keychainAccount
        self.preferredModel = preferredModel
        self.lastCapabilities = lastCapabilities
        self.lastVerifiedAt = lastVerifiedAt
    }
}
