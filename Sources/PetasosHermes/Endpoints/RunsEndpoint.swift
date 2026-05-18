import Foundation
import PetasosCore

/// HTTP plumbing for the /v1/runs/* surface. The streaming consumer lives in
/// RunEventStream.swift so the protocol-level pieces can be unit-tested without
/// needing a live server.
public struct RunsEndpoint: Sendable {
    public let baseURL: URL
    public let bearerToken: String
    private let session: URLSession

    public init(baseURL: URL, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        self.session = session
    }

    public func submit(_ submission: RunSubmission) async throws -> RunHandle {
        var request = try makeRequest(path: "/v1/runs")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(submission)
        return try await performJSON(request)
    }

    public func status(runID: String) async throws -> RunStatus {
        var request = try makeRequest(path: "/v1/runs/\(runID)")
        request.httpMethod = "GET"
        return try await performJSON(request)
    }

    public func stop(runID: String) async throws {
        var request = try makeRequest(path: "/v1/runs/\(runID)/stop")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await performData(request)
    }

    /// Returns the streaming events URL request. Caller is responsible for
    /// driving the SSE byte stream (see RunEventStream).
    public func eventsRequest(runID: String) throws -> URLRequest {
        var request = try makeRequest(path: "/v1/runs/\(runID)/events")
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60 * 30 // 30min; tool-heavy runs can be long
        return request
    }

    // MARK: - HTTP helpers

    private func makeRequest(path: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HermesError.invalidURL(baseURL.absoluteString)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + path
        guard let url = components.url else {
            throw HermesError.invalidURL(baseURL.absoluteString + path)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        return request
    }

    private func performJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await performData(request)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw HermesError.decodeFailure(String(describing: error)) }
    }

    private func performData(_ request: URLRequest) async throws -> Data {
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
        case 200..<300: return data
        case 401: throw HermesError.unauthorized
        case 403: throw HermesError.forbidden
        case 404: throw HermesError.notFound(path: request.url?.path ?? "")
        default:
            let env = try? JSONDecoder().decode(HermesErrorEnvelope.self, from: data)
            throw HermesError.server(status: http.statusCode, message: env?.error.message)
        }
    }
}
