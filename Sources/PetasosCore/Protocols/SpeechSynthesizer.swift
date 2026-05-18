import Foundation

/// Streaming TTS provider. Accepts an AsyncStream of text chunks (from SSE token deltas or full strings)
/// and produces audio frames as they become available.
/// P0: protocol only — implementations land in P2.
public protocol SpeechSynthesizer: AnyObject, Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var availableVoices: [Voice] { get async }
    var isReady: Bool { get async }

    func prepare() async throws
    func synthesize(text: AsyncStream<String>, voice: Voice) -> AsyncThrowingStream<AudioFrame, Error>
    func shutdown() async
}

public struct Voice: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let language: String       // BCP-47, e.g. "en-US"
    public let gender: Gender?
    public let providerIdentifier: String

    public enum Gender: String, Codable, Sendable {
        case female, male, neutral
    }

    public init(id: String, displayName: String, language: String, gender: Gender? = nil, providerIdentifier: String) {
        self.id = id
        self.displayName = displayName
        self.language = language
        self.gender = gender
        self.providerIdentifier = providerIdentifier
    }
}
