import XCTest
@testable import PetasosCore

final class CapabilitiesDecodingTests: XCTestCase {
    func test_decodes_realHermesCapabilitiesResponse() throws {
        // Fixture captured from a live Hermes server (e.g. http://your-hermes-server:8642/v1/capabilities)
        let json = """
        {"object": "hermes.api_server.capabilities", "platform": "hermes-agent", "model": "hermes-agent", "auth": {"type": "bearer", "required": true}, "runtime": {"mode": "server_agent", "tool_execution": "server", "split_runtime": false, "description": "The API server creates a server-side Hermes AIAgent; tools execute on the API-server host unless a future explicit split-runtime mode is enabled."}, "features": {"chat_completions": true, "chat_completions_streaming": true, "responses_api": true, "responses_streaming": true, "run_submission": true, "run_status": true, "run_events_sse": true, "run_stop": true, "run_approval_response": true, "tool_progress_events": true, "approval_events": true, "session_continuity_header": "X-Hermes-Session-Id", "session_key_header": "X-Hermes-Session-Key", "cors": false}, "endpoints": {"health": {"method": "GET", "path": "/health"}}}
        """.data(using: .utf8)!

        let caps = try JSONDecoder().decode(Capabilities.self, from: json)

        XCTAssertEqual(caps.platform, "hermes-agent")
        XCTAssertEqual(caps.model, "hermes-agent")
        XCTAssertEqual(caps.auth.type, "bearer")
        XCTAssertTrue(caps.auth.required)
        XCTAssertEqual(caps.runtime?.mode, "server_agent")
        XCTAssertEqual(caps.runtime?.splitRuntime, false)
        XCTAssertTrue(caps.features.chatCompletions)
        XCTAssertEqual(caps.features.chatCompletionsStreaming, true)
        XCTAssertEqual(caps.features.sessionContinuityHeader, "X-Hermes-Session-Id")
        XCTAssertEqual(caps.endpoints?["health"]?.path, "/health")
    }

    func test_decodes_minimalCapabilities_withMissingOptionalFields() throws {
        let json = """
        {"object": "hermes.api_server.capabilities", "platform": "hermes-agent", "model": "hermes-agent", "auth": {"type": "bearer", "required": true}, "features": {"chat_completions": true, "responses_api": true, "run_submission": true, "run_status": true, "run_events_sse": true, "run_stop": true}}
        """.data(using: .utf8)!

        let caps = try JSONDecoder().decode(Capabilities.self, from: json)
        XCTAssertNil(caps.runtime)
        XCTAssertNil(caps.endpoints)
        XCTAssertNil(caps.features.chatCompletionsStreaming)
        XCTAssertTrue(caps.features.responsesApi)
    }

    func test_decodesModelsList() throws {
        let json = """
        {"object": "list", "data": [{"id": "hermes-agent", "object": "model", "created": 1779041859, "owned_by": "hermes", "permission": [], "root": "hermes-agent", "parent": null}]}
        """.data(using: .utf8)!

        let list = try JSONDecoder().decode(ModelsList.self, from: json)
        XCTAssertEqual(list.data.count, 1)
        XCTAssertEqual(list.data.first?.id, "hermes-agent")
        XCTAssertEqual(list.data.first?.ownedBy, "hermes")
    }

    func test_decodesDetailedHealth() throws {
        let json = """
        {"status": "ok", "platform": "hermes-agent", "gateway_state": "running", "platforms": {"telegram": {"state": "connected", "error_code": null, "error_message": null, "updated_at": "2026-05-17T17:47:31.254695+00:00"}, "signal": {"state": "fatal", "error_code": "signal-phone_lock", "error_message": "Signal account already in use (PID 728). Stop the other gateway first.", "updated_at": "2026-04-18T04:30:56.097866+00:00"}}, "active_agents": 0, "exit_reason": null, "updated_at": "2026-05-17T17:47:35.152558+00:00", "pid": 36667}
        """.data(using: .utf8)!

        let health = try JSONDecoder().decode(DetailedHealth.self, from: json)
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.gatewayState, "running")
        XCTAssertEqual(health.activeAgents, 0)
        XCTAssertEqual(health.pid, 36667)
        XCTAssertEqual(health.platforms?["telegram"]?.state, "connected")
        XCTAssertEqual(health.platforms?["signal"]?.errorCode, "signal-phone_lock")
    }

    func test_decodesHealthStatus_isOK() throws {
        let json = #"{"status": "ok", "platform": "hermes-agent"}"#.data(using: .utf8)!
        let h = try JSONDecoder().decode(HealthStatus.self, from: json)
        XCTAssertTrue(h.isOK)
        XCTAssertEqual(h.platform, "hermes-agent")
    }
}
