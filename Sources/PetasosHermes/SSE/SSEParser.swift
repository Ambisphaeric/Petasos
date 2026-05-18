import Foundation

/// Server-Sent Events line parser. Pure value type, no I/O — feed it bytes or strings
/// from URLSession's bytes stream and it emits `Event`s as they complete.
/// Used in P1 for /v1/runs/{id}/events.
///
/// Parses at the UTF-8 byte level because Swift's `String` treats `\r\n` as a single
/// grapheme cluster, which makes line-end detection on `String` itself unreliable.
public struct SSEParser {
    public struct Event: Sendable, Equatable {
        public var id: String?
        public var event: String?
        public var data: String
        public var retry: Int?
    }

    private var bytes: [UInt8] = []
    private var current = PartialEvent()

    public init() {}

    /// Append a UTF-8 string chunk.
    public mutating func feed(_ chunk: String) -> [Event] {
        bytes.append(contentsOf: chunk.utf8)
        return drain()
    }

    /// Append a raw data chunk (preferred for URLSession.bytes).
    public mutating func feed(_ chunk: Data) -> [Event] {
        bytes.append(contentsOf: chunk)
        return drain()
    }

    private mutating func drain() -> [Event] {
        var emitted: [Event] = []
        var consumed = 0
        var i = 0

        while i < bytes.count {
            let byte = bytes[i]
            if byte == 0x0A { // LF
                let lineEnd = (i > consumed && bytes[i - 1] == 0x0D) ? i - 1 : i
                let line = decode(consumed..<lineEnd)
                consumed = i + 1
                processLine(line, emitted: &emitted)
                i += 1
            } else if byte == 0x0D {
                // CR not followed by LF — SSE spec treats lone CR as a line ending.
                if i + 1 < bytes.count && bytes[i + 1] == 0x0A {
                    // CRLF; the LF branch above will handle the actual line emit.
                    i += 1
                } else {
                    let line = decode(consumed..<i)
                    consumed = i + 1
                    processLine(line, emitted: &emitted)
                    i += 1
                }
            } else {
                i += 1
            }
        }

        if consumed > 0 {
            bytes.removeFirst(consumed)
        }
        return emitted
    }

    private func decode(_ range: Range<Int>) -> String {
        if range.isEmpty { return "" }
        return String(decoding: bytes[range], as: UTF8.self)
    }

    private mutating func processLine(_ line: String, emitted: inout [Event]) {
        if line.isEmpty {
            if let event = current.finalize() {
                emitted.append(event)
            }
            current = PartialEvent()
            return
        }
        if line.first == ":" { return } // comment
        current.absorb(line)
    }

    private struct PartialEvent {
        var id: String?
        var event: String?
        var dataLines: [String] = []
        var retry: Int?

        mutating func absorb(_ line: String) {
            // Split into field and value on the first `:`
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let field = String(parts[0])
            var value = parts.count > 1 ? String(parts[1]) : ""
            if value.hasPrefix(" ") { value.removeFirst() }
            switch field {
            case "id": id = value
            case "event": event = value
            case "data": dataLines.append(value)
            case "retry": retry = Int(value)
            default: break
            }
        }

        func finalize() -> Event? {
            if dataLines.isEmpty && id == nil && event == nil { return nil }
            return Event(
                id: id,
                event: event,
                data: dataLines.joined(separator: "\n"),
                retry: retry
            )
        }
    }
}
