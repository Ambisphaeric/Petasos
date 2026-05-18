import Foundation

public struct Capabilities: Codable, Sendable, Equatable {
    public let object: String
    public let platform: String
    public let model: String
    public let auth: AuthInfo
    public let runtime: Runtime?
    public let features: Features
    public let endpoints: [String: Endpoint]?

    public struct AuthInfo: Codable, Sendable, Equatable {
        public let type: String
        public let required: Bool
    }

    public struct Runtime: Codable, Sendable, Equatable {
        public let mode: String?
        public let toolExecution: String?
        public let splitRuntime: Bool?
        public let description: String?

        enum CodingKeys: String, CodingKey {
            case mode
            case toolExecution = "tool_execution"
            case splitRuntime = "split_runtime"
            case description
        }
    }

    public struct Features: Codable, Sendable, Equatable {
        public let chatCompletions: Bool
        public let chatCompletionsStreaming: Bool?
        public let responsesApi: Bool
        public let responsesStreaming: Bool?
        public let runSubmission: Bool
        public let runStatus: Bool
        public let runEventsSse: Bool
        public let runStop: Bool
        public let runApprovalResponse: Bool?
        public let toolProgressEvents: Bool?
        public let approvalEvents: Bool?
        public let sessionContinuityHeader: String?
        public let sessionKeyHeader: String?
        public let cors: Bool?

        enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case chatCompletionsStreaming = "chat_completions_streaming"
            case responsesApi = "responses_api"
            case responsesStreaming = "responses_streaming"
            case runSubmission = "run_submission"
            case runStatus = "run_status"
            case runEventsSse = "run_events_sse"
            case runStop = "run_stop"
            case runApprovalResponse = "run_approval_response"
            case toolProgressEvents = "tool_progress_events"
            case approvalEvents = "approval_events"
            case sessionContinuityHeader = "session_continuity_header"
            case sessionKeyHeader = "session_key_header"
            case cors
        }
    }

    public struct Endpoint: Codable, Sendable, Equatable {
        public let method: String
        public let path: String
    }
}
