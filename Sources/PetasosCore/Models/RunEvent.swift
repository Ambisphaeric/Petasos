import Foundation

/// Typed view of a hermes run event. We map the wire-level SSE event into one of these
/// before exposing it to the UI, so views never need to know about JSON shapes.
///
/// The OpenAI-Responses-style events we expect from hermes' /v1/runs/{id}/events stream:
///   response.created
///   response.output_text.delta        — token deltas
///   response.output_item.added        — new function_call / message item appears
///   response.output_item.done         — function_call_output settled
///   response.completed                — run done, payload mirrors RunStatus
///   hermes.tool.progress              — tool start/progress hint
///   hermes.approval.requested         — human-in-loop approval needed
///   error
public enum RunEvent: Sendable, Equatable {
    case runCreated(runID: String?)
    case textDelta(String)
    case reasoningAvailable(text: String)
    case itemAdded(ItemKind, raw: String)
    case itemDone(ItemKind, raw: String)
    case toolProgress(ToolProgress)
    case approvalRequested(ApprovalRequest)
    case completed(finalText: String?, usage: TokenUsage?)
    case error(message: String)
    case unknown(eventName: String, raw: String)

    public enum ItemKind: String, Sendable, Equatable {
        case functionCall = "function_call"
        case functionCallOutput = "function_call_output"
        case message
        case unknown
    }

    public struct ToolProgress: Sendable, Equatable {
        public let toolName: String
        public let phase: String?    // "started" | "running" | "completed"
        public let callID: String?
        public let arguments: String?

        public init(toolName: String, phase: String?, callID: String?, arguments: String?) {
            self.toolName = toolName
            self.phase = phase
            self.callID = callID
            self.arguments = arguments
        }
    }

    public struct ApprovalRequest: Sendable, Equatable {
        public let approvalID: String
        public let toolName: String?
        public let description: String?

        public init(approvalID: String, toolName: String?, description: String?) {
            self.approvalID = approvalID
            self.toolName = toolName
            self.description = description
        }
    }
}
