import XCTest
import PetasosCore
@testable import PetasosHermes

/// Fixtures here are copied verbatim from a live hermes /v1/runs/{id}/events stream.
final class RunEventDecoderTests: XCTestCase {
    private let decoder = RunEventDecoder()

    // MARK: - Hermes-native events (captured from live server)

    func test_decodes_messageDelta() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "message.delta", "run_id": "run_abc", "timestamp": 1779044073.00531, "delta": "Herm"}"#,
            retry: nil
        )
        if case .textDelta(let t) = decoder.decode(raw) {
            XCTAssertEqual(t, "Herm")
        } else { XCTFail("Expected .textDelta") }
    }

    func test_decodes_reasoningAvailable() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "reasoning.available", "run_id": "run_abc", "timestamp": 1779044073.107094, "text": "Hermes is online. What do you want to test?"}"#,
            retry: nil
        )
        if case .reasoningAvailable(let text) = decoder.decode(raw) {
            XCTAssertEqual(text, "Hermes is online. What do you want to test?")
        } else { XCTFail("Expected .reasoningAvailable") }
    }

    func test_decodes_toolStarted() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "tool.started", "run_id": "run_abc", "timestamp": 1779044129.521735, "tool": "terminal", "preview": "ls /tmp"}"#,
            retry: nil
        )
        if case .toolProgress(let p) = decoder.decode(raw) {
            XCTAssertEqual(p.toolName, "terminal")
            XCTAssertEqual(p.phase, "started")
            XCTAssertEqual(p.arguments, "ls /tmp")
        } else { XCTFail("Expected .toolProgress") }
    }

    func test_decodes_toolCompletedWithDuration() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "tool.completed", "run_id": "run_abc", "timestamp": 1779044129.8139389, "tool": "terminal", "duration": 0.29, "error": false}"#,
            retry: nil
        )
        if case .toolProgress(let p) = decoder.decode(raw) {
            XCTAssertEqual(p.toolName, "terminal")
            XCTAssertTrue(p.phase?.hasPrefix("completed") ?? false, "Expected 'completed (0.29s)', got \(String(describing: p.phase))")
        } else { XCTFail("Expected .toolProgress") }
    }

    func test_decodes_toolCompleted_errorTrue() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "tool.completed", "run_id": "run_abc", "tool": "terminal", "duration": 0.1, "error": true}"#,
            retry: nil
        )
        if case .toolProgress(let p) = decoder.decode(raw) {
            XCTAssertEqual(p.phase, "error")
        } else { XCTFail("Expected .toolProgress") }
    }

    func test_decodes_runCompleted_extractsOutputAndUsage() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "run.completed", "run_id": "run_abc", "timestamp": 1779044073.1133099, "output": "Hermes is online.", "usage": {"input_tokens": 25976, "output_tokens": 290, "total_tokens": 26266}}"#,
            retry: nil
        )
        if case .completed(let text, let usage) = decoder.decode(raw) {
            XCTAssertEqual(text, "Hermes is online.")
            XCTAssertEqual(usage?.inputTokens, 25976)
            XCTAssertEqual(usage?.outputTokens, 290)
            XCTAssertEqual(usage?.totalTokens, 26266)
        } else { XCTFail("Expected .completed") }
    }

    func test_decodes_runFailed() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event": "run.failed", "run_id": "run_abc", "error": "model timed out"}"#,
            retry: nil
        )
        if case .error(let msg) = decoder.decode(raw) {
            XCTAssertEqual(msg, "model timed out")
        } else { XCTFail("Expected .error") }
    }

    // MARK: - OpenAI-Responses forward compatibility

    func test_decodes_openAI_responseOutputTextDelta_viaSSEHeader() {
        let raw = SSEParser.Event(
            id: nil, event: "response.output_text.delta",
            data: #"{"delta":"Hello"}"#,
            retry: nil
        )
        if case .textDelta(let t) = decoder.decode(raw) {
            XCTAssertEqual(t, "Hello")
        } else { XCTFail("Expected .textDelta") }
    }

    func test_decodes_openAI_responseCompleted() {
        let json = """
        {"response":{"output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Hello world."}]}],"usage":{"input_tokens":12,"output_tokens":5,"total_tokens":17}}}
        """
        let raw = SSEParser.Event(id: nil, event: "response.completed", data: json, retry: nil)
        if case .completed(let text, let usage) = decoder.decode(raw) {
            XCTAssertEqual(text, "Hello world.")
            XCTAssertEqual(usage?.totalTokens, 17)
        } else { XCTFail("Expected .completed") }
    }

    // MARK: - Robustness

    func test_unknownEventName_fallsBackToUnknown() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event":"totally.made.up","run_id":"x"}"#,
            retry: nil
        )
        if case .unknown(let name, _) = decoder.decode(raw) {
            XCTAssertEqual(name, "totally.made.up")
        } else { XCTFail("Expected .unknown") }
    }

    func test_malformedJSON_doesNotCrash() {
        let raw = SSEParser.Event(id: nil, event: nil, data: "{not json}", retry: nil)
        if case .unknown(let name, _) = decoder.decode(raw) {
            XCTAssertEqual(name, "") // no event field findable, no SSE header
        } else { XCTFail("Expected .unknown safely") }
    }

    func test_messageDelta_emptyDeltaField_yieldsEmptyString() {
        let raw = SSEParser.Event(
            id: nil, event: nil,
            data: #"{"event":"message.delta","run_id":"x"}"#,  // delta missing
            retry: nil
        )
        if case .textDelta(let t) = decoder.decode(raw) {
            XCTAssertEqual(t, "")
        } else { XCTFail("Expected .textDelta with empty fallback") }
    }
}
