import Foundation
import PetasosCore

/// Decodes raw SSE `Event`s into typed `RunEvent`s.
///
/// Hermes encodes the event type inside the data payload as `{"event": "<name>", ...}`,
/// not in the SSE `event:` header. We extract the name from the payload first, falling
/// back to the SSE header for forward-compatibility with OpenAI-Responses-style streams.
///
/// Observed hermes events (P1):
///   message.delta         { delta: string }
///   reasoning.available   { text: string }
///   tool.started          { tool: string, preview?: string }
///   tool.completed        { tool: string, duration: number, error: bool }
///   run.completed         { output: string, usage: { input_tokens, output_tokens, total_tokens } }
///
/// Defensive: any unrecognized name or malformed payload becomes `.unknown`,
/// so the UI never crashes on a server-side surprise.
public struct RunEventDecoder: Sendable {
    public init() {}

    public func decode(_ raw: SSEParser.Event) -> RunEvent {
        let payload = parse(raw.data)
        let name = (payload["event"] as? String) ?? raw.event ?? ""

        switch name {
        // MARK: - Hermes-native events

        case "message.delta":
            let delta = payload["delta"] as? String ?? ""
            return .textDelta(delta)

        case "reasoning.available":
            let text = payload["text"] as? String ?? ""
            return .reasoningAvailable(text: text)

        case "tool.started":
            return .toolProgress(.init(
                toolName: payload["tool"] as? String ?? "tool",
                phase: "started",
                callID: payload["call_id"] as? String,
                arguments: payload["preview"] as? String
            ))

        case "tool.completed":
            let isError = (payload["error"] as? Bool) ?? false
            let duration = (payload["duration"] as? NSNumber)?.doubleValue
            let phase: String = {
                if isError { return "error" }
                if let d = duration { return String(format: "completed (%.2fs)", d) }
                return "completed"
            }()
            return .toolProgress(.init(
                toolName: payload["tool"] as? String ?? "tool",
                phase: phase,
                callID: payload["call_id"] as? String,
                arguments: payload["preview"] as? String
            ))

        case "run.started":
            return .runCreated(runID: payload["run_id"] as? String)

        case "run.completed":
            let output = payload["output"] as? String
            let usage = decodeUsage(payload)
            return .completed(finalText: output, usage: usage)

        case "run.failed", "error":
            let msg = (payload["error"] as? String)
                ?? (payload["message"] as? String)
                ?? raw.data
            return .error(message: msg)

        case "approval.requested", "hermes.approval.requested":
            return .approvalRequested(.init(
                approvalID: (payload["approval_id"] as? String) ?? (payload["id"] as? String) ?? "",
                toolName: (payload["tool"] as? String) ?? (payload["tool_name"] as? String),
                description: payload["description"] as? String
            ))

        // MARK: - OpenAI-Responses-style forward compatibility

        case "response.created":
            return .runCreated(runID: string(payload, path: ["response", "id"]))

        case "response.output_text.delta":
            return .textDelta(payload["delta"] as? String ?? "")

        case "response.output_item.added":
            return .itemAdded(itemKind(payload), raw: raw.data)

        case "response.output_item.done":
            return .itemDone(itemKind(payload), raw: raw.data)

        case "response.completed":
            let finalText = extractFinalText(payload)
            let usage = decodeUsage((payload["response"] as? [String: Any]) ?? [:])
            return .completed(finalText: finalText, usage: usage)

        case "hermes.tool.progress":
            return .toolProgress(.init(
                toolName: (payload["name"] as? String) ?? (payload["tool"] as? String) ?? "tool",
                phase: payload["phase"] as? String,
                callID: payload["call_id"] as? String,
                arguments: payload["arguments"] as? String
            ))

        default:
            return .unknown(eventName: name, raw: raw.data)
        }
    }

    // MARK: - JSON helpers

    private func parse(_ data: String) -> [String: Any] {
        guard let d = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private func string(_ root: [String: Any], path: [String]) -> String? {
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current as? String
    }

    private func itemKind(_ payload: [String: Any]) -> RunEvent.ItemKind {
        let type = (payload["item"] as? [String: Any])?["type"] as? String ?? ""
        return RunEvent.ItemKind(rawValue: type) ?? .unknown
    }

    private func decodeUsage(_ obj: [String: Any]) -> TokenUsage? {
        let usage = (obj["usage"] as? [String: Any]) ?? obj
        let input = (usage["input_tokens"] as? NSNumber)?.intValue
        let output = (usage["output_tokens"] as? NSNumber)?.intValue
        let total = (usage["total_tokens"] as? NSNumber)?.intValue
        if input == nil && output == nil && total == nil { return nil }
        return TokenUsage(inputTokens: input, outputTokens: output, totalTokens: total)
    }

    private func extractFinalText(_ payload: [String: Any]) -> String? {
        guard let response = payload["response"] as? [String: Any],
              let output = response["output"] as? [[String: Any]] else { return nil }
        var collected = ""
        for item in output where (item["type"] as? String) == "message" {
            let contents = item["content"] as? [[String: Any]] ?? []
            for c in contents {
                if let t = c["text"] as? String { collected += t }
            }
        }
        return collected.isEmpty ? nil : collected
    }
}
