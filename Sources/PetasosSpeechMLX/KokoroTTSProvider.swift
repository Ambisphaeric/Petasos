import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioTTS
import PetasosCore
import PetasosSpeech

/// Native MLX Kokoro TTS provider. Defaults to `mlx-community/Kokoro-82M-bf16`.
///
/// Uses `generateSamplesStream` so audio arrives as Float chunks rather than the full
/// MLXArray — this lets TTSPlayer schedule playback as samples are produced (lower
/// latency-to-first-audio than the one-shot `generate`).
public final class KokoroTTSProvider: SpeechSynthesizer, @unchecked Sendable {
    public static let identifier: String = "mlx_kokoro"
    public static let displayName: String = "On-device (Kokoro, MLX)"

    public var availableVoices: [Voice] { get async { Self.kokoroVoices } }
    public var isReady: Bool { get async { model != nil } }

    private let modelRepo: String
    private var model: (any SpeechGenerationModel)?
    private let speakingRate: Double

    public init(
        modelRepo: String = "mlx-community/Kokoro-82M-bf16",
        speakingRate: Double = 1.0
    ) {
        self.modelRepo = modelRepo
        self.speakingRate = speakingRate
    }

    public func prepare() async throws {
        let loaded = try await TTS.loadModel(modelRepo: modelRepo)
        self.model = loaded
    }

    public func shutdown() async {
        self.model = nil
    }

    public func synthesize(
        text: AsyncStream<String>,
        voice: Voice
    ) -> AsyncThrowingStream<AudioFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if model == nil { try await prepare() }
                    guard let model else {
                        throw NSError(domain: "Petasos.MLXKokoro", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
                    }
                    let sampleRate = model.sampleRate

                    for await chunk in text {
                        if Task.isCancelled { break }
                        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        let sampleStream = model.generateSamplesStream(
                            text: trimmed,
                            voice: voice.id,
                            refAudio: nil,
                            refText: nil,
                            language: nil,
                            generationParameters: nil,
                            streamingInterval: 0.5
                        )
                        for try await samples in sampleStream {
                            if Task.isCancelled { break }
                            continuation.yield(AudioFrame(
                                samples: samples,
                                sampleRate: sampleRate,
                                timestamp: ProcessInfo.processInfo.systemUptime
                            ))
                        }
                        // Free per-chunk activations between text segments —
                        // otherwise long replies pile up MLX buffers and the
                        // unified-memory usage grows into the tens of GB.
                        MLX.Memory.clearCache()
                    }
                    continuation.finish()
                    MLX.Memory.clearCache()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Voices Kokoro-82M ships in the `voices/` directory of `mlx-community/Kokoro-82M-bf16`.
    /// Confirmed list from the model README: 9 languages, 54 voices.
    public static let kokoroVoices: [Voice] = {
        let entries: [(String, String, String, Voice.Gender?)] = [
            // American English
            ("af_alloy", "Alloy", "en-US", .female),
            ("af_aoede", "Aoede", "en-US", .female),
            ("af_bella", "Bella", "en-US", .female),
            ("af_heart", "Heart", "en-US", .female),
            ("af_jessica", "Jessica", "en-US", .female),
            ("af_kore", "Kore", "en-US", .female),
            ("af_nicole", "Nicole", "en-US", .female),
            ("af_nova", "Nova", "en-US", .female),
            ("af_river", "River", "en-US", .female),
            ("af_sarah", "Sarah", "en-US", .female),
            ("af_sky", "Sky", "en-US", .female),
            ("am_adam", "Adam", "en-US", .male),
            ("am_echo", "Echo", "en-US", .male),
            ("am_eric", "Eric", "en-US", .male),
            ("am_fenrir", "Fenrir", "en-US", .male),
            ("am_liam", "Liam", "en-US", .male),
            ("am_michael", "Michael", "en-US", .male),
            ("am_onyx", "Onyx", "en-US", .male),
            ("am_puck", "Puck", "en-US", .male),
            ("am_santa", "Santa", "en-US", .male),
            // British English
            ("bf_alice", "Alice", "en-GB", .female),
            ("bf_emma", "Emma", "en-GB", .female),
            ("bf_isabella", "Isabella", "en-GB", .female),
            ("bf_lily", "Lily", "en-GB", .female),
            ("bm_daniel", "Daniel", "en-GB", .male),
            ("bm_fable", "Fable", "en-GB", .male),
            ("bm_george", "George", "en-GB", .male),
            ("bm_lewis", "Lewis", "en-GB", .male),
            // Spanish
            ("ef_dora", "Dora", "es", .female),
            ("em_alex", "Alex", "es", .male),
            ("em_santa", "Santa", "es", .male),
            // French
            ("ff_siwis", "Siwis", "fr", .female),
            // Hindi
            ("hf_alpha", "Alpha", "hi", .female),
            ("hf_beta", "Beta", "hi", .female),
            ("hm_omega", "Omega", "hi", .male),
            ("hm_psi", "Psi", "hi", .male),
            // Italian
            ("if_sara", "Sara", "it", .female),
            ("im_nicola", "Nicola", "it", .male),
            // Japanese
            ("jf_alpha", "Alpha", "ja", .female),
            ("jf_gongitsune", "Gongitsune", "ja", .female),
            ("jf_nezumi", "Nezumi", "ja", .female),
            ("jf_tebukuro", "Tebukuro", "ja", .female),
            ("jm_kumo", "Kumo", "ja", .male),
            // Portuguese
            ("pf_dora", "Dora", "pt", .female),
            ("pm_alex", "Alex", "pt", .male),
            ("pm_santa", "Santa", "pt", .male),
            // Chinese
            ("zf_xiaobei", "Xiaobei", "zh", .female),
            ("zf_xiaoni", "Xiaoni", "zh", .female),
            ("zf_xiaoxiao", "Xiaoxiao", "zh", .female),
            ("zf_xiaoyi", "Xiaoyi", "zh", .female),
            ("zm_yunjian", "Yunjian", "zh", .male),
            ("zm_yunxi", "Yunxi", "zh", .male),
            ("zm_yunxia", "Yunxia", "zh", .male),
            ("zm_yunyang", "Yunyang", "zh", .male),
        ]
        return entries.map { (id, name, lang, gender) in
            Voice(
                id: id,
                displayName: "\(name) (\(lang))",
                language: lang,
                gender: gender,
                providerIdentifier: KokoroTTSProvider.identifier
            )
        }
    }()
}
