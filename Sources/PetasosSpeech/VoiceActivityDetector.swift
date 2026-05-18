import Foundation
import PetasosCore

/// Simple energy-based voice activity detection. Tracks short-time RMS over incoming
/// audio frames; emits `.speechStart` once RMS stays above threshold for >= startMs,
/// and `.speechEnd` once RMS stays below threshold for >= endMs.
///
/// Good enough for always-listening dictation. P2 stretch: replace with a small DSP model
/// like Silero-VAD if false positives become a problem in noisy rooms.
public struct VoiceActivityDetector: Sendable {
    public enum Event: Sendable, Equatable {
        case speechStart
        case speech(rms: Float)
        case speechEnd
        case silence(rms: Float)
    }

    public var startRMSThreshold: Float
    public var endRMSThreshold: Float
    public var minSpeechMs: Int
    public var minSilenceMs: Int

    public init(
        startRMSThreshold: Float = 0.012,
        endRMSThreshold: Float = 0.006,
        minSpeechMs: Int = 120,
        minSilenceMs: Int = 700
    ) {
        self.startRMSThreshold = startRMSThreshold
        self.endRMSThreshold = endRMSThreshold
        self.minSpeechMs = minSpeechMs
        self.minSilenceMs = minSilenceMs
    }

    public final class State: @unchecked Sendable {
        public internal(set) var isInSpeech = false
        var consecutiveAboveMs = 0
        var consecutiveBelowMs = 0
        public init() {}
    }

    public func makeState() -> State { State() }

    /// Process a single audio frame. Returns the event(s) it triggered.
    public func ingest(_ frame: AudioFrame, state: State) -> [Event] {
        let rms = rms(of: frame.samples)
        let frameMs = (frame.samples.count * 1000) / max(frame.sampleRate, 1)
        var events: [Event] = []

        if state.isInSpeech {
            events.append(.speech(rms: rms))
            if rms < endRMSThreshold {
                state.consecutiveBelowMs += frameMs
                state.consecutiveAboveMs = 0
                if state.consecutiveBelowMs >= minSilenceMs {
                    state.isInSpeech = false
                    state.consecutiveBelowMs = 0
                    events.append(.speechEnd)
                }
            } else {
                state.consecutiveBelowMs = 0
            }
        } else {
            events.append(.silence(rms: rms))
            if rms > startRMSThreshold {
                state.consecutiveAboveMs += frameMs
                state.consecutiveBelowMs = 0
                if state.consecutiveAboveMs >= minSpeechMs {
                    state.isInSpeech = true
                    state.consecutiveAboveMs = 0
                    events.append(.speechStart)
                }
            } else {
                state.consecutiveAboveMs = 0
            }
        }
        return events
    }

    private func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}
