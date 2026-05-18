import Foundation
import PetasosCore

/// Coordinates microphone capture with a SpeechRecognizer.
///
/// Two modes:
///   - `startPushToTalk()` — one utterance: mic on, stream straight to recognizer, finalize on `stopAndFinalize()`.
///   - `startAlwaysListening()` — VAD-driven: mic stays warm, each detected
///     speech segment is fed to a fresh recognizer call. Final transcripts
///     arrive as `onUtterance(text)` callbacks; `status` stays `.listening` between utterances.
@MainActor
public final class STTSession: ObservableObject {
    public enum Status: Sendable, Equatable {
        case idle
        case starting
        case listening
        case finalizing
        case error(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public private(set) var liveTranscript: String = ""
    @Published public private(set) var currentRMS: Float = 0

    public var onUtterance: ((String) -> Void)?

    /// When true, the VAD always-on loop drops incoming frames and resets its
    /// state. Used to prevent the TTS output picked up by the mic from being
    /// transcribed back as the user's next utterance — i.e. the acoustic
    /// feedback loop when Kokoro speaks through the speakers and Parakeet
    /// hears it. VoiceController sets this whenever TTSPlayer.status is
    /// `.preparing` or `.speaking`, plus a short cooldown afterwards for room
    /// reverb. Has no effect in push-to-talk mode (frames go straight to the
    /// recognizer with no VAD).
    ///
    /// TODO(aec): once Voice-Processing IO is enabled in MicCapture (see the
    /// TODO(aec) block there), this flag becomes a fallback rather than the
    /// primary defense — keep it for the cross-device case where TTS plays
    /// out to a different output than the AEC reference, but the default
    /// path should be able to leave the mic open and let barge-in work.
    public var isInputGatedByTTS: Bool = false

    private let mic: MicCapture
    private let recognizer: any SpeechRecognizer
    private var runTask: Task<Void, Never>?
    private var alwaysOn: Bool = false

    public init(mic: MicCapture = MicCapture(), recognizer: any SpeechRecognizer) {
        self.mic = mic
        self.recognizer = recognizer
    }

    public func startPushToTalk() async {
        await begin(useVAD: false)
    }

    public func startAlwaysListening() async {
        await begin(useVAD: true)
    }

    /// Stop a push-to-talk session: closes the audio stream and waits for the
    /// final transcript. Critically, this must NOT cancel `runTask`. Cancelling
    /// the outer task propagates as `continuation.onTermination → task.cancel()`
    /// to the recognizer's inner task, which then short-circuits before
    /// running the model. The user would talk, click stop, and see no
    /// transcript ever appear.
    ///
    /// Instead: stop the mic (which closes the audio stream), then await the
    /// recognizer task naturally. Its for-await loop exits when the stream
    /// closes, the model generates, the transcript yields, and the task
    /// completes. For hard abort, use `cancel()`.
    public func stopAndFinalize() async {
        if status == .listening {
            status = .finalizing
        }
        mic.stop()
        await runTask?.value
        runTask = nil
        alwaysOn = false
    }

    /// Hard cancel: stop without waiting for a final transcript.
    public func cancel() {
        mic.stop()
        runTask?.cancel()
        runTask = nil
        liveTranscript = ""
        status = .idle
        alwaysOn = false
    }

    private func begin(useVAD: Bool) async {
        guard status == .idle else { return }
        status = .starting
        liveTranscript = ""
        alwaysOn = useVAD

        let audioStream: AsyncStream<AudioFrame>
        do {
            // Mic first: this fires the macOS microphone permission prompt on
            // first run. Recognizer prep (e.g. Parakeet model download) can
            // take many seconds and used to run first — if it threw or hung,
            // the user clicked the mic but never saw a system prompt and the
            // app appeared "broken." Asking for mic immediately makes that
            // contract obvious.
            audioStream = try await mic.start()
            try await recognizer.prepare()
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            alwaysOn = false
            return
        }
        status = .listening

        if useVAD {
            runTask = Task { [weak self] in
                await self?.runAlwaysOnLoop(audioStream: audioStream)
            }
        } else {
            runTask = Task { [weak self] in
                await self?.runPushToTalk(audioStream: audioStream)
            }
        }
    }

    // MARK: - Push-to-talk

    private func runPushToTalk(audioStream: AsyncStream<AudioFrame>) async {
        let recognizerStream = recognizer.recognize(audio: audioStream)
        do {
            for try await transcript in recognizerStream {
                await MainActor.run {
                    self.liveTranscript = transcript.text
                    if transcript.isFinal {
                        self.onUtterance?(transcript.text)
                        self.status = .idle
                    }
                }
            }
            await MainActor.run {
                if case .listening = self.status { self.status = .idle }
                if case .finalizing = self.status { self.status = .idle }
            }
        } catch {
            await MainActor.run {
                self.status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    // MARK: - Always-on (VAD)

    /// Consume the mic stream once, slicing it into per-utterance sub-streams.
    /// For each speech-start ↔ speech-end pair detected by VAD, we open a fresh
    /// `recognizer.recognize(audio:)` stream, forward frames until the end, then
    /// close it so the recognizer runs `model.generate(...)` on that utterance.
    private func runAlwaysOnLoop(audioStream: AsyncStream<AudioFrame>) async {
        let vad = VoiceActivityDetector()
        let vadState = vad.makeState()

        // Small lookback ring so we don't clip the very first phoneme: the
        // frame that triggers .speechStart was classified as silence (the
        // threshold needs a few frames above), so include the prior ~300ms.
        let lookbackFrameCount = 3
        var lookback: [AudioFrame] = []

        var utteranceContinuation: AsyncStream<AudioFrame>.Continuation?
        var utteranceTask: Task<Void, Never>?

        func startUtterance() {
            let (stream, cont) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(64))
            utteranceContinuation = cont
            // Flush lookback first so leading audio is preserved.
            for f in lookback { cont.yield(f) }
            let recognizerStream = recognizer.recognize(audio: stream)
            utteranceTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await transcript in recognizerStream {
                        await MainActor.run {
                            self.liveTranscript = transcript.text
                            if transcript.isFinal {
                                self.onUtterance?(transcript.text)
                                // Reset for the next utterance.
                                self.liveTranscript = ""
                            }
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                    }
                }
            }
        }

        func finishUtterance() async {
            utteranceContinuation?.finish()
            utteranceContinuation = nil
            await utteranceTask?.value
            utteranceTask = nil
        }

        for await frame in audioStream {
            if Task.isCancelled { break }

            // If TTS is currently playing through the speakers, drop this
            // frame and reset VAD/lookback. Otherwise Kokoro's output would
            // be picked up by the mic and transcribed as a fresh user
            // utterance — Petasos would talk to itself in a loop.
            if isInputGatedByTTS {
                if utteranceContinuation != nil { await finishUtterance() }
                vadState.isInSpeech = false
                vadState.consecutiveAboveMs = 0
                vadState.consecutiveBelowMs = 0
                lookback.removeAll(keepingCapacity: true)
                continue
            }

            let events = vad.ingest(frame, state: vadState)

            // Process transitions in order: .speechStart opens a new utterance,
            // .speechEnd closes the current one.
            for event in events {
                switch event {
                case .speechStart:
                    if utteranceContinuation == nil { startUtterance() }
                case .speechEnd:
                    await finishUtterance()
                case .speech, .silence:
                    break
                }
            }

            // Forward audio while we believe we're in speech.
            if vadState.isInSpeech, let cont = utteranceContinuation {
                cont.yield(frame)
            }

            // Maintain the lookback regardless — it's what we prepend on next start.
            lookback.append(frame)
            if lookback.count > lookbackFrameCount {
                lookback.removeFirst(lookback.count - lookbackFrameCount)
            }
        }

        // Mic stream ended — finalize any in-flight utterance.
        await finishUtterance()
        await MainActor.run {
            if case .listening = self.status { self.status = .idle }
            if case .finalizing = self.status { self.status = .idle }
            self.liveTranscript = ""
        }
    }
}
