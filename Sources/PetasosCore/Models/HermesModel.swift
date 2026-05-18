import Foundation

public struct HermesModel: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let object: String
    public let created: Int
    public let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }

    public init(id: String, object: String = "model", created: Int = 0, ownedBy: String = "hermes") {
        self.id = id
        self.object = object
        self.created = created
        self.ownedBy = ownedBy
    }
}

public struct ModelsList: Codable, Sendable {
    public let object: String
    public let data: [HermesModel]
}
