import AVFoundation
import Foundation
import PetasosCore

/// Drives a SpeechSynthesizer and plays its audio output through AVAudioEngine.
///
/// Accepts text chunks (typically from a `SentenceChunker` fed by an SSE stream) and
/// schedules synthesizer-produced audio frames onto an `AVAudioPlayerNode` for playback.
///
/// Streaming pipeline:
///   text chunk → synthesizer.synthesize → AsyncStream<AudioFrame>
///                                          → schedule into AVAudioPlayerNode
@MainActor
public final class TTSPlayer: ObservableObject {
    public enum Status: Sendable, Equatable {
        case idle
        case preparing
        case speaking
        case error(String)
    }

    @Published public private(set) var status: Status = .idle
    @Published public var voice: Voice?

    private let synthesizer: any SpeechSynthesizer
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var configured = false

    /// External feed channel — caller writes text chunks here.
    private var textContinuation: AsyncStream<String>.Continuation?
    private var renderTask: Task<Void, Never>?

    public init(synthesizer: any SpeechSynthesizer) {
        self.synthesizer = synthesizer
    }

    public func prepare() async throws {
        guard status == .idle else { return }
        status = .preparing
        try await synthesizer.prepare()
        if voice == nil {
            voice = await synthesizer.availableVoices.first
        }
        configureEngineIfNeeded()
        status = .idle
    }

    /// Speak a single text chunk one-shot. For streaming use `beginStreaming` + `feed`.
    public func speak(_ text: String) async throws {
        try await prepare()
        guard let voice else { throw NSError(domain: "Petasos.TTS", code: -1) }
        configureEngineIfNeeded()
        status = .speaking
        let (stream, cont) = AsyncStream<String>.makeStream()
        cont.yield(text)
        cont.finish()
        let audio = synthesizer.synthesize(text: stream, voice: voice)
        await drain(audio: audio)
        status = .idle
    }

    /// Begin a streaming session. Call `feed` repeatedly, then `finish` when SSE ends.
    public func beginStreaming() async throws {
        try await prepare()
        guard let voice else { throw NSError(domain: "Petasos.TTS", code: -1) }
        configureEngineIfNeeded()
        let (stream, cont) = AsyncStream<String>.makeStream()
        textContinuation = cont
        let audio = synthesizer.synthesize(text: stream, voice: voice)
        status = .speaking
        renderTask = Task { [weak self] in
            await self?.drain(audio: audio)
            await MainActor.run { self?.status = .idle }
        }
    }

    public func feed(_ chunk: String) {
        textContinuation?.yield(chunk)
    }

    public func finish() {
        textContinuation?.finish()
        textContinuation = nil
    }

    public func stop() {
        textContinuation?.finish()
        textContinuation = nil
        renderTask?.cancel()
        renderTask = nil
        playerNode.stop()
        status = .idle
    }

    // MARK: - Engine setup

    private func configureEngineIfNeeded() {
        guard !configured else { return }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.outputNode, format: format)
        engine.prepare()
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
        configured = true
    }

    private func drain(audio: AsyncThrowingStream<AudioFrame, Error>) async {
        do {
            for try await frame in audio {
                schedule(frame)
            }
        } catch {
            await MainActor.run {
                self.status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func schedule(_ frame: AudioFrame) {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(frame.sampleRate),
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frame.samples.count)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(frame.samples.count)
        if let dst = buffer.floatChannelData?[0] {
            frame.samples.withUnsafeBufferPointer { src in
                dst.update(from: src.baseAddress!, count: src.count)
            }
        }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }
}
