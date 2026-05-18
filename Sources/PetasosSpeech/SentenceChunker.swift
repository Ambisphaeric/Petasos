import Foundation

/// Splits streaming text into TTS-friendly chunks. We feed Kokoro one clause at a time:
/// long enough to sound natural, short enough that latency-to-first-audio stays low.
///
/// Rules:
///   1. Hard break on `.` `!` `?` `\n\n` `;` (end-of-clause punctuation).
///   2. If the running buffer exceeds `softLimit` chars without hitting a hard break,
///      break on the next `,` or `\n`.
///   3. If the buffer exceeds `hardLimit`, break on the next space.
///   4. `flush()` always emits whatever remains (used at end-of-stream).
public struct SentenceChunker: Sendable {
    public var softLimit: Int
    public var hardLimit: Int

    public init(softLimit: Int = 80, hardLimit: Int = 200) {
        self.softLimit = softLimit
        self.hardLimit = hardLimit
    }

    public final class State: @unchecked Sendable {
        var buffer: String = ""
        public init() {}
    }

    public func makeState() -> State { State() }

    /// Feed an arriving text delta. Returns zero or more complete chunks ready for TTS.
    public func feed(_ delta: String, state: State) -> [String] {
        state.buffer += delta
        return drain(state: state, forceFlush: false)
    }

    /// Emit any remaining text (called when the stream completes).
    public func flush(state: State) -> [String] {
        let trimmed = state.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        state.buffer = ""
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private func drain(state: State, forceFlush: Bool) -> [String] {
        var chunks: [String] = []
        while let breakRange = findBreak(in: state.buffer) {
            let chunk = String(state.buffer[..<breakRange.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            state.buffer.removeSubrange(state.buffer.startIndex..<breakRange.upperBound)
            if !chunk.isEmpty { chunks.append(chunk) }
        }
        return chunks
    }

    private func findBreak(in text: String) -> Range<String.Index>? {
        // 1) hard punctuation
        let hardChars: [Character] = [".", "!", "?", ";"]
        if let idx = text.firstIndex(where: { hardChars.contains($0) }) {
            // Include trailing closing-quote / paren if any to avoid orphans.
            var end = text.index(after: idx)
            while end < text.endIndex, "\")'”’".contains(text[end]) {
                end = text.index(after: end)
            }
            return idx..<end
        }
        // 2) paragraph break (two newlines)
        if let idx = text.range(of: "\n\n") {
            return idx
        }
        // 3) over soft limit -> next comma / single newline
        if text.count >= softLimit {
            if let idx = text.firstIndex(where: { $0 == "," || $0 == "\n" }) {
                return idx..<text.index(after: idx)
            }
        }
        // 4) over hard limit -> next space
        if text.count >= hardLimit {
            if let idx = text.firstIndex(of: " ") {
                return idx..<text.index(after: idx)
            }
        }
        return nil
    }
}
