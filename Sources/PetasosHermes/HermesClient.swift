import Foundation
import PetasosCore

/// Concrete ChatTransport implementation backed by URLSession.
/// Thread-safe (Sendable) — capture and reuse across actors.
public final class HermesClient: ChatTransport, @unchecked Sendable {
    public let baseURL: URL
    private let bearerToken: String
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    public func health() async throws -> HealthStatus {
        try await get("/health", authenticated: false)
    }

    public func detailedHealth() async throws -> DetailedHealth {
        try await get("/health/detailed", authenticated: true)
    }

    public func capabilities() async throws -> Capabilities {
        try await get("/v1/capabilities", authenticated: true)
    }

    public func models() async throws -> [HermesModel] {
        let list: ModelsList = try await get("/v1/models", authenticated: true)
        return list.data
    }

    // MARK: - HTTP plumbing

    private func get<T: Decodable>(_ path: String, authenticated: Bool) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HermesError.invalidURL(baseURL.absoluteString)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + path
        guard let url = components.url else {
            throw HermesError.invalidURL(baseURL.absoluteString + path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .timedOut {
            throw HermesError.timeout
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw HermesError.cancelled
        } catch {
            throw HermesError.notReachable(underlying: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HermesError.notReachable(underlying: "Non-HTTP response")
        }

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw HermesError.decodeFailure(String(describing: error))
            }
        case 401:
            throw HermesError.unauthorized
        case 403:
            throw HermesError.forbidden
        case 404:
            throw HermesError.notFound(path: path)
        default:
            let envelope = try? decoder.decode(HermesErrorEnvelope.self, from: data)
            throw HermesError.server(status: http.statusCode, message: envelope?.error.message)
        }
    }
}
