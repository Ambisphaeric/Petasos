import Foundation

/// On-device or remote STT provider. Implementations register with SpeechProviderRegistry at startup.
/// P0: protocol only — implementations land in P2 (PetasosSpeechMLX).
public protocol SpeechRecognizer: AnyObject, Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isReady: Bool { get async }

    func prepare() async throws
    func recognize(audio: AsyncStream<AudioFrame>) -> AsyncThrowingStream<Transcript, Error>
    func shutdown() async
}

public struct AudioFrame: Sendable {
    public let samples: [Float]   // mono, 16 kHz expected
    public let sampleRate: Int
    public let timestamp: TimeInterval

    public init(samples: [Float], sampleRate: Int, timestamp: TimeInterval) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = timestamp
    }
}

public struct Transcript: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool
    public let confidence: Double?

    public init(text: String, isFinal: Bool, confidence: Double? = nil) {
        self.text = text
        self.isFinal = isFinal
        self.confidence = confidence
    }
}
