@preconcurrency import AVFoundation
import Foundation
import PetasosCore

/// Captures microphone audio via AVAudioEngine and resamples it to mono 16 kHz Float32 —
/// the format Parakeet expects. Emits `AudioFrame`s through an `AsyncStream`.
///
/// One `MicCapture` may be active at a time; subsequent `start()` calls return the
/// same stream. The engine is kept warm between sessions to avoid hardware spin-up cost.
@MainActor
public final class MicCapture {
    public enum CaptureError: Error, LocalizedError {
        case permissionDenied
        case engineStartFailed(String)
        case converterUnavailable

        public var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Microphone access denied."
            case .engineStartFailed(let m): return "Audio engine failed to start: \(m)"
            case .converterUnavailable: return "Could not configure 16 kHz audio converter."
            }
        }
    }

    public static let targetSampleRate: Double = 16_000
    public static let targetFrameSize: AVAudioFrameCount = 1600 // 100ms at 16kHz

    private final class PullState: @unchecked Sendable {
        var pulled = false
    }

    /// Best-effort counter for diagnostic logging from the audio thread. Not
    /// atomic — a missed increment is fine, this only drives a log every Nth
    /// frame.
    nonisolated(unsafe) private static var diagFrameCount: Int = 0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var continuation: AsyncStream<AudioFrame>.Continuation?
    private var stream: AsyncStream<AudioFrame>?
    private var isRunning = false

    public init() {}

    public var running: Bool { isRunning }

    /// Begin capture. Returns the audio stream. Subsequent calls while running return the existing stream.
    public func start() async throws -> AsyncStream<AudioFrame> {
        if let stream { return stream }

        let permission = AudioPermissions.current()
        if permission == .notDetermined {
            _ = await AudioPermissions.request()
        }
        guard AudioPermissions.current() == .authorized else {
            throw CaptureError.permissionDenied
        }

        let input = engine.inputNode
        // TODO(aec): enable Apple's Voice-Processing IO here to get real
        // acoustic echo cancellation + ducking + AGC. Replaces the time-based
        // mic gate in STTSession/VoiceController (search isInputGatedByTTS /
        // ttsTailGateMs) and unlocks barge-in — user can interrupt Kokoro
        // mid-sentence.
        //
        // Sketch:
        //   if #available(macOS 13.0, *) {
        //       try? input.setVoiceProcessingEnabled(true)
        //       // Optional tuning:
        //       //   input.isVoiceProcessingBypassed = false
        //       //   input.isVoiceProcessingAGCEnabled = true
        //       //   input.voiceProcessingOtherAudioDuckingConfiguration =
        //       //       .init(enableAdvancedDucking: true, duckingLevel: .default)
        //   }
        //
        // Caveats to handle before shipping:
        //   1. setVoiceProcessingEnabled changes the inputNode's output format
        //      (typically forces it to 1-ch, 16 kHz or 24 kHz). Re-query
        //      `input.outputFormat(forBus: 0)` AFTER toggling and rebuild the
        //      AVAudioConverter against the new format.
        //   2. Some external audio devices (USB mics, Bluetooth headsets) and
        //      virtual loopback devices reject voice processing. The call
        //      throws — fall back to the current path (no VP, keep the
        //      time-based gate) on failure rather than crashing.
        //   3. VP routes through the AUVoiceIO unit which adds ~10–20 ms of
        //      latency. Probably fine for chat, but worth measuring against
        //      the push-to-talk responsiveness people are used to.
        //   4. The reference signal AEC subtracts is whatever the system is
        //      playing through the *default* output device. If the user has
        //      Kokoro routing to a different device (e.g. AirPods while the
        //      mic is the MBP built-in) AEC won't see TTS as a reference and
        //      the gate is still needed as a safety net.
        let inputFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.converterUnavailable
        }
        self.converter = converter

        let (stream, continuation) = AsyncStream<AudioFrame>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.stream = stream
        self.continuation = continuation

        // CRITICAL: install the tap from a nonisolated static helper. If we
        // call `installTap` inline here, the closure inherits @MainActor from
        // this enclosing method — Swift 6 then emits an executor check at the
        // top of the closure that traps (Trace/BPT trap 5) when AVFoundation
        // invokes it from its RealtimeMessenger queue. The static helper
        // breaks that inheritance chain.
        Self.installTap(
            on: input,
            inputFormat: inputFormat,
            converter: converter,
            targetFormat: targetFormat,
            continuation: continuation
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.stream = nil
            self.continuation = nil
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
        return stream
    }

    /// Stop capture. The active stream's continuation is finished so consumers exit cleanly.
    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        stream = nil
        continuation = nil
        converter = nil
        isRunning = false
    }

    /// Defined here (not inline in `start()`) so the closure passed to
    /// AVAudioInputNode does not inherit MainActor isolation. The closure is
    /// invoked on AVFoundation's audio thread; if it were @MainActor, Swift 6
    /// would trap at the top of the call.
    nonisolated private static func installTap(
        on input: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        continuation: AsyncStream<AudioFrame>.Continuation
    ) {
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            process(
                inputBuffer: buffer,
                converter: converter,
                targetFormat: targetFormat,
                continuation: continuation
            )
        }
    }

    /// Runs on the audio thread. Pure: takes an input buffer + resampling
    /// machinery, emits a frame on the AsyncStream. Must remain `nonisolated`
    /// and free of any reference to `self`, or Swift 6's runtime executor
    /// check will trap when the tap fires.
    nonisolated private static func process(
        inputBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        continuation: AsyncStream<AudioFrame>.Continuation
    ) {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 16)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return }

        var error: NSError?
        let pullState = PullState()
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if pullState.pulled {
                outStatus.pointee = .noDataNow
                return nil
            }
            pullState.pulled = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        guard status != .error, outBuffer.frameLength > 0 else { return }

        guard let channelData = outBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outBuffer.frameLength)))
        let frame = AudioFrame(
            samples: samples,
            sampleRate: Int(targetFormat.sampleRate),
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        // Diagnostic: print a one-line summary every ~10 frames (≈1s of audio
        // at 100ms per frame). Tagged with "petasos.mic" so it's grep-able when
        // running from terminal. Includes a peak amplitude so the user can see
        // their voice is actually reaching the pipeline.
        var peak: Float = 0
        for s in samples { let a = abs(s); if a > peak { peak = a } }
        Self.diagFrameCount += 1
        if Self.diagFrameCount % 10 == 0 {
            print("[petasos.mic] frame #\(Self.diagFrameCount): \(samples.count) samples @ \(Int(targetFormat.sampleRate))Hz, peak=\(String(format: "%.3f", peak))")
        }
        // AsyncStream.Continuation.yield is documented thread-safe.
        continuation.yield(frame)
    }
}
