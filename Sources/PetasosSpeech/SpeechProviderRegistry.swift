import Foundation
import PetasosCore

/// Registry of available speech provider types. Provider modules register their types
/// at app launch (e.g. ParakeetSTTProvider, HTTPSTTProvider). Settings UI reads from
/// this registry to populate backend pickers.
@MainActor
public final class SpeechProviderRegistry: ObservableObject {
    public struct STTOption: Sendable, Identifiable, Equatable {
        public let id: String
        public let displayName: String
        public let factory: @MainActor @Sendable (SpeechBackendConfig) throws -> any SpeechRecognizer

        public init(
            id: String,
            displayName: String,
            factory: @escaping @MainActor @Sendable (SpeechBackendConfig) throws -> any SpeechRecognizer
        ) {
            self.id = id
            self.displayName = displayName
            self.factory = factory
        }

        public static func == (lhs: STTOption, rhs: STTOption) -> Bool { lhs.id == rhs.id }
    }

    public struct TTSOption: Sendable, Identifiable, Equatable {
        public let id: String
        public let displayName: String
        public let factory: @MainActor @Sendable (SpeechBackendConfig) throws -> any SpeechSynthesizer

        public init(
            id: String,
            displayName: String,
            factory: @escaping @MainActor @Sendable (SpeechBackendConfig) throws -> any SpeechSynthesizer
        ) {
            self.id = id
            self.displayName = displayName
            self.factory = factory
        }

        public static func == (lhs: TTSOption, rhs: TTSOption) -> Bool { lhs.id == rhs.id }
    }

    public static let shared = SpeechProviderRegistry()

    @Published public private(set) var sttOptions: [STTOption] = []
    @Published public private(set) var ttsOptions: [TTSOption] = []

    public func register(stt: STTOption) {
        if !sttOptions.contains(where: { $0.id == stt.id }) {
            sttOptions.append(stt)
        }
    }

    public func register(tts: TTSOption) {
        if !ttsOptions.contains(where: { $0.id == tts.id }) {
            ttsOptions.append(tts)
        }
    }
}

/// Generic config bag passed to a provider's factory. Providers pick the fields they
/// need; unused fields are ignored.
public struct SpeechBackendConfig: Sendable, Equatable {
    public var modelID: String?            // HF repo id, e.g. "mlx-community/parakeet-tdt_ctc-110m"
    public var voiceID: String?            // Kokoro voice id, e.g. "af_bella"
    public var endpointURL: URL?           // For HTTP backend
    public var bearerToken: String?        // For HTTP backend
    public var speakingRate: Double        // 1.0 = normal

    public init(
        modelID: String? = nil,
        voiceID: String? = nil,
        endpointURL: URL? = nil,
        bearerToken: String? = nil,
        speakingRate: Double = 1.0
    ) {
        self.modelID = modelID
        self.voiceID = voiceID
        self.endpointURL = endpointURL
        self.bearerToken = bearerToken
        self.speakingRate = speakingRate
    }
}
