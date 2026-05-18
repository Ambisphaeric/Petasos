import Foundation

public enum HermesError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case notReachable(underlying: String)
    case unauthorized
    case forbidden
    case notFound(path: String)
    case server(status: Int, message: String?)
    case decodeFailure(String)
    case timeout
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .notReachable(let u): return "Cannot reach hermes server. \(u)"
        case .unauthorized: return "Bearer token rejected. Check your API key."
        case .forbidden: return "Forbidden by hermes server."
        case .notFound(let p): return "Endpoint not found: \(p)"
        case .server(let status, let msg): return "Hermes returned \(status): \(msg ?? "no message")"
        case .decodeFailure(let detail): return "Could not decode hermes response. \(detail)"
        case .timeout: return "Request timed out."
        case .cancelled: return "Request cancelled."
        }
    }
}

/// OpenAI-compatible error envelope returned by hermes on 4xx/5xx.
public struct HermesErrorEnvelope: Codable, Sendable {
    public let error: ErrorBody

    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let type: String?
        public let code: String?
    }
}
