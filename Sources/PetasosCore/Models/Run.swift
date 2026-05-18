import Foundation

/// Submission to POST /v1/runs.
public struct RunSubmission: Codable, Sendable, Equatable {
    public var input: String
    public var instructions: String?
    public var sessionID: String?
    public var conversation: String?
    public var previousResponseID: String?
    public var model: String?

    public init(
        input: String,
        instructions: String? = nil,
        sessionID: String? = nil,
        conversation: String? = nil,
        previousResponseID: String? = nil,
        model: String? = nil
    ) {
        self.input = input
        self.instructions = instructions
        self.sessionID = sessionID
        self.conversation = conversation
        self.previousResponseID = previousResponseID
        self.model = model
    }

    enum CodingKeys: String, CodingKey {
        case input, instructions, model, conversation
        case sessionID = "session_id"
        case previousResponseID = "previous_response_id"
    }
}

/// Initial response from POST /v1/runs.
public struct RunHandle: Codable, Sendable, Equatable {
    public let runID: String
    public let status: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case status
    }
}

/// Polling response from GET /v1/runs/{id}.
public struct RunStatus: Codable, Sendable, Equatable {
    public let object: String?
    public let runID: String
    public let status: Status
    public let sessionID: String?
    public let model: String?
    public let output: String?
    public let usage: TokenUsage?
    public let error: String?

    public enum Status: String, Codable, Sendable {
        case started
        case running
        case completed
        case failed
        case cancelled
        case awaitingApproval = "awaiting_approval"
        case unknown
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case object, status, model, output, usage, error
        case runID = "run_id"
        case sessionID = "session_id"
    }
}

public struct TokenUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int?, outputTokens: Int?, totalTokens: Int?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}
