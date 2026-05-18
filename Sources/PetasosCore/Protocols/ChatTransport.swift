import Foundation

/// Abstraction over the hermes HTTP API. Concrete implementation lives in PetasosHermes.
/// Protocol exists in Core so other modules can depend on it without pulling in URLSession code.
public protocol ChatTransport: Sendable {
    var baseURL: URL { get }
    func health() async throws -> HealthStatus
    func detailedHealth() async throws -> DetailedHealth
    func capabilities() async throws -> Capabilities
    func models() async throws -> [HermesModel]
}
