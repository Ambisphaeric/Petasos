import Foundation
@preconcurrency import MLX
import PetasosCore
import PetasosSpeech

/// Convenience to register the MLX STT/TTS providers with the global registry at app launch.
@MainActor
public enum MLXSpeechRegistration {
    public static func register() {
        // MLX caches GPU buffers between operations to amortize allocation. The
        // default ceiling tracks the device's memory limit (≈1.5× of the
        // working set), so on a Mac with lots of RAM the cache can balloon to
        // 20+ GB after a few Parakeet/Kokoro runs — exactly what we were
        // seeing. Cap it at 256 MB. Inference paths additionally clearCache()
        // after each model invocation so transient activations don't stick.
        MLX.Memory.cacheLimit = 256 * 1024 * 1024
        print("[petasos.mlx] cacheLimit set to \(MLX.Memory.cacheLimit / (1024*1024)) MB")

        SpeechProviderRegistry.shared.register(stt: SpeechProviderRegistry.STTOption(
            id: ParakeetSTTProvider.identifier,
            displayName: ParakeetSTTProvider.displayName,
            factory: { config in
                let repo = config.modelID ?? "mlx-community/parakeet-tdt_ctc-110m"
                return ParakeetSTTProvider(modelRepo: repo)
            }
        ))

        SpeechProviderRegistry.shared.register(tts: SpeechProviderRegistry.TTSOption(
            id: KokoroTTSProvider.identifier,
            displayName: KokoroTTSProvider.displayName,
            factory: { config in
                let repo = config.modelID ?? "mlx-community/Kokoro-82M-bf16"
                return KokoroTTSProvider(modelRepo: repo, speakingRate: config.speakingRate)
            }
        ))
    }
}
