import Foundation

/// User-selected speech configuration, persisted to UserDefaults.
/// Used by AppEnvironment to construct the active STT/TTS providers at launch.
public struct SpeechPreferences: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case onDeviceMLX = "on_device_mlx"
        case httpSidecar = "http_sidecar"
        case disabled
    }

    /// How the user triggers speech input.
    public enum InputMode: String, Codable, Sendable, CaseIterable {
        /// Click the mic button to start; click again to stop and send.
        case clickToggle = "click_toggle"
        /// Hold the configured global hotkey to talk; release to send.
        case pushToTalk = "push_to_talk"
        /// VAD auto-detects utterance boundaries while the chat is open.
        case alwaysOn = "always_on"
    }

    /// A keyboard combo captured from `NSEvent.keyDown`. Stored as Carbon-style
    /// virtual key code + Carbon modifier mask so it can round-trip to
    /// `RegisterEventHotKey` without re-deriving on every launch.
    public struct HotkeyCombo: Codable, Sendable, Equatable {
        public var keyCode: UInt32      // virtual key code (kVK_*)
        public var carbonModifiers: UInt32  // cmdKey | shiftKey | optionKey | controlKey
        public var displayString: String    // pre-rendered "⌃⌥Space"-style string for the UI

        public init(keyCode: UInt32, carbonModifiers: UInt32, displayString: String) {
            self.keyCode = keyCode
            self.carbonModifiers = carbonModifiers
            self.displayString = displayString
        }

        /// Default: ⌃⌥Space (control+option+space). Avoids Spotlight (⌘Space),
        /// Quick Note (Q hot-corner), and Mission Control (F-keys).
        public static let `default` = HotkeyCombo(
            keyCode: 0x31,                  // kVK_Space
            carbonModifiers: (1 << 12) | (1 << 11),  // controlKey | optionKey (Carbon bits)
            displayString: "⌃⌥Space"
        )
    }

    public var sttMode: Mode
    public var ttsMode: Mode
    public var sttModelID: String       // HF repo id, e.g. "mlx-community/parakeet-tdt_ctc-110m"
    public var ttsModelID: String
    public var ttsVoiceID: String
    public var ttsSpeakingRate: Double
    public var httpSTTURL: String
    public var httpTTSURL: String
    public var reuseHermesBearerForHTTP: Bool

    /// Input trigger mode for STT.
    public var inputMode: InputMode
    /// Hotkey used when `inputMode == .pushToTalk`.
    public var pushToTalkHotkey: HotkeyCombo
    /// When true, append `instructionSuffix` to every user message sent to the
    /// assistant. The user's own UI bubble still shows the bare text — only the
    /// payload to Hermes is augmented.
    public var appendInstructionSuffix: Bool
    /// Text appended to outgoing user messages. Empty string is treated as
    /// disabled even if the toggle is on.
    public var instructionSuffix: String
    /// Milliseconds to keep the STT mic gated after TTS finishes speaking.
    /// Larger values prevent the trailing tail of Kokoro's last word + room
    /// reverb from being picked up as a new user utterance; too large delays
    /// when you can speak again. Reasonable range: 200–1500 ms.
    public var ttsTailGateMs: Int

    public init(
        sttMode: Mode = .onDeviceMLX,
        ttsMode: Mode = .onDeviceMLX,
        sttModelID: String = "mlx-community/parakeet-tdt_ctc-110m",
        ttsModelID: String = "mlx-community/Kokoro-82M-bf16",
        ttsVoiceID: String = "af_bella",
        ttsSpeakingRate: Double = 1.0,
        httpSTTURL: String = "http://localhost:8001",
        httpTTSURL: String = "http://localhost:8002",
        reuseHermesBearerForHTTP: Bool = true,
        inputMode: InputMode = .clickToggle,
        pushToTalkHotkey: HotkeyCombo = .default,
        appendInstructionSuffix: Bool = true,
        instructionSuffix: String = "Please keep your response concise, to a maximum of 4 lines. Be conversational.",
        ttsTailGateMs: Int = 400
    ) {
        self.sttMode = sttMode
        self.ttsMode = ttsMode
        self.sttModelID = sttModelID
        self.ttsModelID = ttsModelID
        self.ttsVoiceID = ttsVoiceID
        self.ttsSpeakingRate = ttsSpeakingRate
        self.httpSTTURL = httpSTTURL
        self.httpTTSURL = httpTTSURL
        self.reuseHermesBearerForHTTP = reuseHermesBearerForHTTP
        self.inputMode = inputMode
        self.pushToTalkHotkey = pushToTalkHotkey
        self.appendInstructionSuffix = appendInstructionSuffix
        self.instructionSuffix = instructionSuffix
        self.ttsTailGateMs = ttsTailGateMs
    }

    public static let `default` = SpeechPreferences()

    /// Decoded payload may be missing the newly-added fields if the user
    /// upgraded from an older build. Decode tolerantly so we don't reset their
    /// whole speech config on first launch of the new version.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SpeechPreferences.default
        self.sttMode = (try? c.decode(Mode.self, forKey: .sttMode)) ?? defaults.sttMode
        self.ttsMode = (try? c.decode(Mode.self, forKey: .ttsMode)) ?? defaults.ttsMode
        self.sttModelID = (try? c.decode(String.self, forKey: .sttModelID)) ?? defaults.sttModelID
        self.ttsModelID = (try? c.decode(String.self, forKey: .ttsModelID)) ?? defaults.ttsModelID
        self.ttsVoiceID = (try? c.decode(String.self, forKey: .ttsVoiceID)) ?? defaults.ttsVoiceID
        self.ttsSpeakingRate = (try? c.decode(Double.self, forKey: .ttsSpeakingRate)) ?? defaults.ttsSpeakingRate
        self.httpSTTURL = (try? c.decode(String.self, forKey: .httpSTTURL)) ?? defaults.httpSTTURL
        self.httpTTSURL = (try? c.decode(String.self, forKey: .httpTTSURL)) ?? defaults.httpTTSURL
        self.reuseHermesBearerForHTTP = (try? c.decode(Bool.self, forKey: .reuseHermesBearerForHTTP)) ?? defaults.reuseHermesBearerForHTTP
        self.inputMode = (try? c.decode(InputMode.self, forKey: .inputMode)) ?? defaults.inputMode
        self.pushToTalkHotkey = (try? c.decode(HotkeyCombo.self, forKey: .pushToTalkHotkey)) ?? defaults.pushToTalkHotkey
        self.appendInstructionSuffix = (try? c.decode(Bool.self, forKey: .appendInstructionSuffix)) ?? defaults.appendInstructionSuffix
        self.instructionSuffix = (try? c.decode(String.self, forKey: .instructionSuffix)) ?? defaults.instructionSuffix
        self.ttsTailGateMs = (try? c.decode(Int.self, forKey: .ttsTailGateMs)) ?? defaults.ttsTailGateMs
    }

    private enum CodingKeys: String, CodingKey {
        case sttMode, ttsMode, sttModelID, ttsModelID, ttsVoiceID, ttsSpeakingRate
        case httpSTTURL, httpTTSURL, reuseHermesBearerForHTTP
        case inputMode, pushToTalkHotkey, appendInstructionSuffix, instructionSuffix
        case ttsTailGateMs
    }
}

/// UserDefaults-backed store for SpeechPreferences.
public final class SpeechPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "petasos.speech.preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> SpeechPreferences {
        guard let data = defaults.data(forKey: key),
              let prefs = try? JSONDecoder().decode(SpeechPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    public func save(_ prefs: SpeechPreferences) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: key)
    }
}
