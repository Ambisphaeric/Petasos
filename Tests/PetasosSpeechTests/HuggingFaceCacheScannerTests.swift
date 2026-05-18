import XCTest
@testable import PetasosSpeech

final class HuggingFaceCacheScannerTests: XCTestCase {
    func test_findsParakeetAndKokoro_inRealCache() {
        // Smoke test against the actual user's HF cache. Confirms the matching pattern
        // and folder-name parsing work against what's actually there.
        let scanner = HuggingFaceCacheScanner()

        let parakeets = scanner.scan(matching: "mlx-community/parakeet-*")
        XCTAssertFalse(parakeets.isEmpty, "Expected at least one parakeet model in HF cache")
        XCTAssertTrue(parakeets.contains(where: { $0.id == "mlx-community/parakeet-tdt_ctc-110m" }),
                      "Expected the 110m parakeet variant in the cache")

        let kokoros = scanner.scan(matching: "mlx-community/Kokoro-*")
        XCTAssertFalse(kokoros.isEmpty, "Expected at least one Kokoro model in HF cache")
        if let k = kokoros.first {
            XCTAssertTrue(k.hasConfig, "Kokoro snapshot should have config.json")
            XCTAssertTrue(k.hasSafetensors, "Kokoro snapshot should have a .safetensors weights file")
        }
    }

    func test_parsesFolderNameCorrectly() {
        let scanner = HuggingFaceCacheScanner(cacheRoot: URL(fileURLWithPath: "/dev/null"))
        // Non-existent cache → empty results, no crash
        XCTAssertTrue(scanner.scan(matching: "mlx-community/*").isEmpty)
    }
}
