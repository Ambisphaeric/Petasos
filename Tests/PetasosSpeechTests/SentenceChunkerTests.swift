import XCTest
@testable import PetasosSpeech

final class SentenceChunkerTests: XCTestCase {
    func test_breaksOnPeriod() {
        let chunker = SentenceChunker()
        let state = chunker.makeState()
        var chunks: [String] = []
        chunks.append(contentsOf: chunker.feed("Hello world. ", state: state))
        chunks.append(contentsOf: chunker.feed("Next sentence.", state: state))
        chunks.append(contentsOf: chunker.flush(state: state))
        XCTAssertEqual(chunks, ["Hello world.", "Next sentence."])
    }

    func test_breaksOnQuestion() {
        let chunker = SentenceChunker()
        let state = chunker.makeState()
        let chunks = chunker.feed("How are you? ", state: state)
        XCTAssertEqual(chunks, ["How are you?"])
    }

    func test_paragraphBreak() {
        let chunker = SentenceChunker()
        let state = chunker.makeState()
        let chunks = chunker.feed("First.\n\nSecond.", state: state)
        // First.\n\n breaks at \n\n; then "Second." breaks on period.
        XCTAssertEqual(chunks, ["First.", "Second."])
    }

    func test_softLimit_breaksOnComma() {
        let chunker = SentenceChunker(softLimit: 20)
        let state = chunker.makeState()
        let chunks = chunker.feed("This is a sentence with no terminator yet, but here is a comma", state: state)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks[0].hasSuffix(","))
    }

    func test_flushEmits_partial() {
        let chunker = SentenceChunker()
        let state = chunker.makeState()
        let streaming = chunker.feed("Partial text without terminator", state: state)
        XCTAssertTrue(streaming.isEmpty)
        let flushed = chunker.flush(state: state)
        XCTAssertEqual(flushed, ["Partial text without terminator"])
    }

    func test_streamingFeedAccumulates() {
        let chunker = SentenceChunker()
        let state = chunker.makeState()
        XCTAssertTrue(chunker.feed("This ", state: state).isEmpty)
        XCTAssertTrue(chunker.feed("is ", state: state).isEmpty)
        XCTAssertTrue(chunker.feed("a ", state: state).isEmpty)
        XCTAssertTrue(chunker.feed("clause", state: state).isEmpty)
        let chunks = chunker.feed(". Next.", state: state)
        XCTAssertEqual(chunks, ["This is a clause.", "Next."])
    }
}
