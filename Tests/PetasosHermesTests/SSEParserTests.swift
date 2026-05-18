import XCTest
@testable import PetasosHermes

final class SSEParserTests: XCTestCase {
    func test_emitsCompleteEvent_onBlankLine() {
        var parser = SSEParser()
        let chunk = "event: hermes.tool.progress\ndata: {\"name\":\"terminal\"}\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "hermes.tool.progress")
        XCTAssertEqual(events.first?.data, #"{"name":"terminal"}"#)
    }

    func test_handlesMultilineData() {
        var parser = SSEParser()
        let chunk = "data: line1\ndata: line2\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "line1\nline2")
    }

    func test_handlesIDAndRetry() {
        var parser = SSEParser()
        let chunk = "id: 42\nretry: 5000\ndata: hi\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "42")
        XCTAssertEqual(events.first?.retry, 5000)
        XCTAssertEqual(events.first?.data, "hi")
    }

    func test_ignoresCommentLines() {
        var parser = SSEParser()
        let chunk = ": keep-alive comment\ndata: real\n\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.data, "real")
    }

    func test_streamingChunksAcrossFeeds() {
        var parser = SSEParser()
        var events = parser.feed("event: foo\ndata: par")
        XCTAssertTrue(events.isEmpty, "Should not emit before blank line")
        events = parser.feed("tial\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "foo")
        XCTAssertEqual(events.first?.data, "partial")
    }

    func test_handlesCarriageReturn() {
        var parser = SSEParser()
        let chunk = "event: foo\r\ndata: bar\r\n\r\n"
        let events = parser.feed(chunk)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.event, "foo")
        XCTAssertEqual(events.first?.data, "bar")
    }
}
