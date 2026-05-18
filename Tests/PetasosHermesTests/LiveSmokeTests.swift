import XCTest
import PetasosCore
@testable import PetasosHermes

/// Smoke tests against a real hermes-agent server. Skipped unless both env vars are set:
///   PETASOS_LIVE_URL    = http://your-hermes-server:8642
///   PETASOS_LIVE_BEARER = your-bearer-token
///
/// Run with:
///   PETASOS_LIVE_URL=http://your-hermes-server:8642 \
///   PETASOS_LIVE_BEARER=localYapper-123 \
///   swift test --filter LiveSmokeTests
final class LiveSmokeTests: XCTestCase {
    private func makeClient() throws -> HermesClient {
        let env = ProcessInfo.processInfo.environment
        guard let urlString = env["PETASOS_LIVE_URL"],
              let url = URL(string: urlString),
              let bearer = env["PETASOS_LIVE_BEARER"] else {
            throw XCTSkip("Set PETASOS_LIVE_URL and PETASOS_LIVE_BEARER to run live smoke tests.")
        }
        return HermesClient(baseURL: url, bearerToken: bearer)
    }

    func test_live_health() async throws {
        let client = try makeClient()
        let health = try await client.health()
        XCTAssertTrue(health.isOK)
        XCTAssertEqual(health.platform, "hermes-agent")
    }

    func test_live_capabilities() async throws {
        let client = try makeClient()
        let caps = try await client.capabilities()
        XCTAssertEqual(caps.platform, "hermes-agent")
        XCTAssertTrue(caps.features.chatCompletions)
        XCTAssertTrue(caps.features.runEventsSse)
    }

    func test_live_models() async throws {
        let client = try makeClient()
        let models = try await client.models()
        XCTAssertFalse(models.isEmpty)
        XCTAssertEqual(models.first?.id, "hermes-agent")
    }

    func test_live_unauthorized() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let urlString = env["PETASOS_LIVE_URL"], let url = URL(string: urlString) else {
            throw XCTSkip("Set PETASOS_LIVE_URL to run live unauthorized test.")
        }
        let bogus = HermesClient(baseURL: url, bearerToken: "definitely-not-the-key")
        do {
            _ = try await bogus.capabilities()
            XCTFail("Expected unauthorized error")
        } catch HermesError.unauthorized {
            // expected
        } catch {
            XCTFail("Expected .unauthorized, got \(error)")
        }
    }

    func test_live_autoDiscover_skipsUnreachable() async throws {
        // 8643 should not be running locally — verifies AutoDiscover returns empty on miss.
        let discoverer = AutoDiscover(timeout: 0.5)
        let bogus = URL(string: "http://127.0.0.1:8643")!
        let results = await discoverer.probe([bogus])
        XCTAssertTrue(results.isEmpty, "Expected no candidates for unreachable port")
    }

    func test_live_runs_endToEnd() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let urlString = env["PETASOS_LIVE_URL"],
              let url = URL(string: urlString),
              let bearer = env["PETASOS_LIVE_BEARER"] else {
            throw XCTSkip("Set PETASOS_LIVE_URL and PETASOS_LIVE_BEARER to run end-to-end test.")
        }

        let endpoint = RunsEndpoint(baseURL: url, bearerToken: bearer)
        let handle = try await endpoint.submit(RunSubmission(
            input: "Reply with exactly the word: PING"
        ))
        XCTAssertFalse(handle.runID.isEmpty)

        var streamedText = ""
        var sawCompleted = false
        var unknownEvents: [String] = []
        var toolNames: [String] = []
        var finalUsage: TokenUsage?

        for try await event in RunEventStream.subscribe(runID: handle.runID, endpoint: endpoint) {
            switch event {
            case .textDelta(let t):
                streamedText += t
            case .reasoningAvailable(let t):
                if streamedText.isEmpty { streamedText = t }
            case .toolProgress(let p):
                toolNames.append("\(p.toolName):\(p.phase ?? "?")")
            case .completed(let final, let usage):
                if let final, streamedText.isEmpty { streamedText = final }
                finalUsage = usage
                sawCompleted = true
            case .unknown(let name, _):
                unknownEvents.append(name)
            case .error(let msg):
                XCTFail("Run errored: \(msg)")
            default:
                break
            }
        }

        XCTAssertTrue(sawCompleted, "Expected at least one .completed event")
        XCTAssertFalse(streamedText.isEmpty, "Expected non-empty assistant response")
        XCTAssertNotNil(finalUsage?.totalTokens, "Expected token usage in run.completed")
        if !unknownEvents.isEmpty {
            print("ℹ️ Decoded \(unknownEvents.count) .unknown events (names: \(Set(unknownEvents))) — consider adding cases.")
        }
        print("✅ live run output: \(streamedText)")
    }
}
