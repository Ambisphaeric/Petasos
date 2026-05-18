import Foundation
import PetasosCore
import PetasosSpeech

/// Convenience to register the HTTP STT/TTS providers with the global registry.
/// Called at app launch from PetasosApp.
@MainActor
public enum HTTPSpeechRegistration {
    public static func register() {
        SpeechProviderRegistry.shared.register(stt: SpeechProviderRegistry.STTOption(
            id: HTTPSTTProvider.identifier,
            displayName: HTTPSTTProvider.displayName,
            factory: { config in
                guard let url = config.endpointURL else {
                    throw NSError(domain: "Petasos.HTTPSTT", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing endpoint URL"])
                }
                return HTTPSTTProvider(endpointURL: url, bearer: config.bearerToken)
            }
        ))

        SpeechProviderRegistry.shared.register(tts: SpeechProviderRegistry.TTSOption(
            id: HTTPTTSProvider.identifier,
            displayName: HTTPTTSProvider.displayName,
            factory: { config in
                guard let url = config.endpointURL else {
                    throw NSError(domain: "Petasos.HTTPTTS", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing endpoint URL"])
                }
                return HTTPTTSProvider(endpointURL: url, bearer: config.bearerToken, speakingRate: config.speakingRate)
            }
        ))
    }
}
