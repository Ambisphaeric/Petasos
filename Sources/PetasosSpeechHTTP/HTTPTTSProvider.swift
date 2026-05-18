import Foundation
import PetasosCore
import PetasosSpeech

/// TTS backed by a Kokoro-compatible HTTP sidecar (POST /tts-json → WAV bytes).
///
/// For each incoming text chunk, posts a JSON request, decodes the WAV response,
/// and yields AudioFrames to the caller (typically TTSPlayer).
public final class HTTPTTSProvider: SpeechSynthesizer, @unchecked Sendable {
    public static let identifier: String = "http_tts"
    public static let displayName: String = "HTTP sidecar (Kokoro)"

    public var availableVoices: [Voice] { get async {
        // The HTTP sidecar exposes voice info via GET /tts/voices in mac-speech-services,
        // but to keep startup cheap we ship a curated default set. Settings can override.
        Self.defaultKokoroVoices
    } }
    public var isReady: Bool { get async { true } }

    private let endpointURL: URL
    private let bearer: String?
    private let session: URLSession
    private let speakingRate: Double

    public init(endpointURL: URL, bearer: String? = nil, speakingRate: Double = 1.0, session: URLSession = .shared) {
        self.endpointURL = endpointURL
        self.bearer = bearer
        self.session = session
        self.speakingRate = speakingRate
    }

    public func prepare() async throws {}
    public func shutdown() async {}

    public func synthesize(text: AsyncStream<String>, voice: Voice) -> AsyncThrowingStream<AudioFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for await chunk in text {
                        if Task.isCancelled { break }
                        let frame = try await self.synthesizeOne(text: chunk, voiceID: voice.id)
                        continuation.yield(frame)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func synthesizeOne(text: String, voiceID: String) async throws -> AudioFrame {
        let url = endpointURL.appendingPathComponent("tts-json")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["text": text, "voice": voiceID, "speed": speakingRate]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(
                domain: "Petasos.HTTPTTS",
                code: code,
                userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "TTS failed"]
            )
        }
        let decoded = try WAV.decode(data)
        return AudioFrame(
            samples: decoded.samples,
            sampleRate: decoded.sampleRate,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Curated subset of Kokoro voices we know exist in mlx-community/Kokoro-82M-bf16.
    /// The MLX provider populates from the actual voices/ dir at runtime; this list is the
    /// fallback used when only the HTTP backend is selected.
    public static let defaultKokoroVoices: [Voice] = [
        Voice(id: "af_bella", displayName: "Bella (US female)", language: "en-US", gender: .female, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "af_sarah", displayName: "Sarah (US female)", language: "en-US", gender: .female, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "af_nicole", displayName: "Nicole (US female)", language: "en-US", gender: .female, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "am_michael", displayName: "Michael (US male)", language: "en-US", gender: .male, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "am_adam", displayName: "Adam (US male)", language: "en-US", gender: .male, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "bf_emma", displayName: "Emma (UK female)", language: "en-GB", gender: .female, providerIdentifier: HTTPTTSProvider.identifier),
        Voice(id: "bm_george", displayName: "George (UK male)", language: "en-GB", gender: .male, providerIdentifier: HTTPTTSProvider.identifier),
    ]
}
