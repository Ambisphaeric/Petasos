import Foundation
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT
import PetasosCore
import PetasosSpeech

/// Native MLX Parakeet STT provider. Defaults to `mlx-community/parakeet-tdt_ctc-110m`
/// — the 110m TDT-CTC variant — but works with any Parakeet listed in the
/// `mlx-audio-swift` Parakeet README.
///
/// Loading the model is async and downloads weights on first launch (or reuses the
/// HuggingFace cache if already present). Subsequent loads are in-memory.
public final class ParakeetSTTProvider: SpeechRecognizer, @unchecked Sendable {
    public static let identifier: String = "mlx_parakeet"
    public static let displayName: String = "On-device (Parakeet, MLX)"

    public var isReady: Bool { get async { model != nil } }

    private let modelRepo: String
    private var model: ParakeetModel?

    public init(modelRepo: String = "mlx-community/parakeet-tdt_ctc-110m") {
        self.modelRepo = modelRepo
    }

    public func prepare() async throws {
        let loaded = try await ParakeetModel.fromPretrained(modelRepo)
        self.model = loaded
    }

    public func shutdown() async {
        self.model = nil
    }

    public func recognize(audio: AsyncStream<AudioFrame>) -> AsyncThrowingStream<Transcript, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Accumulate the entire utterance. Parakeet operates on a full audio array.
                    // For always-listening mode, callers should chunk audio at VAD boundaries
                    // by closing the stream between utterances.
                    var samples: [Float] = []
                    samples.reserveCapacity(16_000 * 10)
                    var sampleRate = 16_000

                    var frameNo = 0
                    for await frame in audio {
                        if Task.isCancelled { break }
                        samples.append(contentsOf: frame.samples)
                        sampleRate = frame.sampleRate
                        frameNo += 1
                        if frameNo % 10 == 0 {
                            print("[petasos.stt] received frame #\(frameNo), accumulated \(samples.count) samples (≈\(samples.count / max(sampleRate,1))s)")
                        }
                    }
                    if Task.isCancelled {
                        print("[petasos.stt] cancelled before generation")
                        continuation.finish()
                        return
                    }
                    guard !samples.isEmpty else {
                        print("[petasos.stt] no samples received — finishing with no transcript")
                        continuation.finish()
                        return
                    }
                    print("[petasos.stt] stream closed; generating from \(samples.count) samples (≈\(samples.count / max(sampleRate,1))s)…")
                    // Ensure the model is loaded.
                    if model == nil { try await prepare() }
                    guard let model else {
                        throw NSError(domain: "Petasos.MLXParakeet", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
                    }

                    // [Float] → MLXArray (1D); Parakeet's preprocessor expects 16 kHz.
                    let audioArray = MLXArray(samples)
                    _ = sampleRate // Parakeet config defines its own sample rate; we resampled to 16k upstream.

                    let output = model.generate(
                        audio: audioArray,
                        generationParameters: STTGenerateParameters()
                    )
                    print("[petasos.stt] transcript: '\(output.text)'")
                    continuation.yield(Transcript(text: output.text, isFinal: true, confidence: nil))
                    continuation.finish()
                    // Drop intermediate activations so the cache doesn't grow
                    // unbounded across utterances.
                    MLX.Memory.clearCache()
                    let activeMB = MLX.Memory.activeMemory / (1024 * 1024)
                    let cacheMB = MLX.Memory.cacheMemory / (1024 * 1024)
                    print("[petasos.stt] post-clear MLX active=\(activeMB)MB cache=\(cacheMB)MB")
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
