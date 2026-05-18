import XCTest
@testable import PetasosHermes

final class HermesErrorTests: XCTestCase {
    func test_decodes_realHermesUnauthorizedEnvelope() throws {
        let json = #"{"error": {"message": "Invalid API key", "type": "invalid_request_error", "code": "invalid_api_key"}}"#
            .data(using: .utf8)!
        let envelope = try JSONDecoder().decode(HermesErrorEnvelope.self, from: json)
        XCTAssertEqual(envelope.error.message, "Invalid API key")
        XCTAssertEqual(envelope.error.type, "invalid_request_error")
        XCTAssertEqual(envelope.error.code, "invalid_api_key")
    }

    func test_unauthorizedErrorDescription() {
        let err = HermesError.unauthorized
        XCTAssertEqual(err.errorDescription, "Bearer token rejected. Check your API key.")
    }
}
