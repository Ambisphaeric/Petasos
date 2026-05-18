import Foundation
import PetasosCore
import PetasosSpeech

/// Per-popover voice coordinator. Owns one STTSession and one TTSPlayer, both
/// constructed from the user's SpeechPreferences. The popover's mic button and the
/// streaming-TTS coordinator both drive this.
///
/// AppEnvironment rebuilds this whenever SpeechPreferences change so we don't carry
/// around stale provider instances.
@MainActor
public final class VoiceController: ObservableObject {
    @Published public private(set) var sttStatus: STTSession.Status = .idle
    @Published public private(set) var ttsStatus: TTSPlayer.Status = .idle
    @Published public private(set) var liveTranscript: String = ""

    /// Whether to speak streaming responses with the configured TTS.
    @Published public var speakResponses: Bool = true

    /// What "start listening" means for the current user preference. Set by
    /// AppEnvironment from `SpeechPreferences.inputMode`. The popover's mic
    /// button calls `startListening()` regardless of mode; this picks the
    /// underlying STT path so always-on stays always-on across button clicks.
    public enum StartMode: Sendable {
        case oneShot       // one utterance, finalize on stopListeningAndSend
        case continuous    // VAD-segmented, runs until cancel
    }
    public var startMode: StartMode = .oneShot

    public let sttSession: STTSession?
    public let ttsPlayer: TTSPlayer?

    /// Called when an STT utterance is finalized. The popover sets this to ChatSession.send.
    public var onUtterance: ((String) -> Void)?

    private var sttObservation: Task<Void, Never>?
    private var ttsObservation: Task<Void, Never>?
    private var ttsCooldownTask: Task<Void, Never>?
    private let chunker = SentenceChunker()
    private var chunkerState: SentenceChunker.State?

    /// How long after TTS goes idle to keep the mic gate held. Room reverb and
    /// the trailing tail of Kokoro's last word can otherwise re-trigger VAD.
    /// Defaults to 400 ms (good for built-in MacBook speakers); AppEnvironment
    /// pushes the user-configured value from SpeechPreferences after init.
    public var ttsTailGateMs: UInt64 = 400

    public init(stt: STTSession?, tts: TTSPlayer?) {
        self.sttSession = stt
        self.ttsPlayer = tts

        if let stt {
            sttObservation = Task { @MainActor [weak self] in
                guard let self else { return }
                for await status in stt.$status.values {
                    self.sttStatus = status
                }
            }
            stt.onUtterance = { [weak self] text in
                self?.handleFinalTranscript(text)
            }
        }

        if let tts {
            ttsObservation = Task { @MainActor [weak self] in
                guard let self else { return }
                for await status in tts.$status.values {
                    self.ttsStatus = status
                    self.updateInputGate(forTTS: status)
                }
            }
        }
    }

    /// Open or close the STT mic gate based on the current TTS status. While
    /// TTS is preparing/speaking, frames are dropped so the speaker output
    /// doesn't feed back through the microphone. After TTS returns to idle we
    /// wait `ttsTailGateMs` before re-opening — the buffered audio still in
    /// the AVAudioPlayerNode queue takes a moment to finish playing back.
    ///
    /// TODO(aec): when we wire up Apple's Voice-Processing IO in MicCapture
    /// (TODO(aec) there), this whole function should become opt-in rather
    /// than always-on. AEC does the right thing in real time without
    /// silencing the user, so barge-in (interrupting Kokoro mid-sentence by
    /// just talking) starts working. Keep the gate available for users whose
    /// TTS output device differs from the AEC reference device.
    private func updateInputGate(forTTS status: TTSPlayer.Status) {
        guard let stt = sttSession else { return }
        switch status {
        case .preparing, .speaking:
            ttsCooldownTask?.cancel()
            ttsCooldownTask = nil
            stt.isInputGatedByTTS = true
        case .idle, .error:
            ttsCooldownTask?.cancel()
            ttsCooldownTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.ttsTailGateMs * 1_000_000)
                if Task.isCancelled { return }
                self.sttSession?.isInputGatedByTTS = false
            }
        }
    }

    deinit {
        sttObservation?.cancel()
        ttsObservation?.cancel()
        ttsCooldownTask?.cancel()
    }

    public var isAvailable: Bool { sttSession != nil }
    public var isListening: Bool {
        switch sttStatus {
        case .listening, .starting, .finalizing: return true
        default: return false
        }
    }

    // MARK: - Mic input

    public func startListening() async {
        guard let stt = sttSession else { return }
        liveTranscript = ""
        switch startMode {
        case .oneShot: await stt.startPushToTalk()
        case .continuous: await stt.startAlwaysListening()
        }
    }

    public func stopListeningAndSend() async {
        guard let stt = sttSession else { return }
        await stt.stopAndFinalize()
    }

    public func cancelListening() {
        sttSession?.cancel()
        liveTranscript = ""
    }

    private func handleFinalTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveTranscript = trimmed
        onUtterance?(trimmed)
    }

    // MARK: - Streaming TTS

    /// Begin a new TTS streaming session. Caller feeds incoming SSE text deltas
    /// via `appendForSpeech(_:)`, then calls `finishSpeaking()` when the stream ends.
    public func beginSpeaking() async {
        guard speakResponses, let tts = ttsPlayer else { return }
        chunkerState = chunker.makeState()
        do {
            try await tts.beginStreaming()
        } catch {
            // TTS is best-effort; failure shouldn't break the chat.
        }
    }

    /// Feed an SSE text delta. Internally batches into clause-sized chunks before
    /// handing to the synthesizer — keeps latency-to-first-audio low without
    /// fragmenting prosody mid-word.
    public func appendForSpeech(_ delta: String) {
        guard speakResponses, let tts = ttsPlayer, let state = chunkerState else { return }
        let chunks = chunker.feed(delta, state: state)
        for chunk in chunks { tts.feed(chunk) }
    }

    public func finishSpeaking() {
        guard let tts = ttsPlayer, let state = chunkerState else { return }
        let remaining = chunker.flush(state: state)
        for chunk in remaining { tts.feed(chunk) }
        tts.finish()
        chunkerState = nil
    }

    public func stopSpeaking() {
        ttsPlayer?.stop()
        chunkerState = nil
    }
}
