import XCTest
import PetasosCore
@testable import PetasosSpeech

final class VoiceActivityDetectorTests: XCTestCase {
    func test_detectsSpeechStartAndEnd() {
        let vad = VoiceActivityDetector(
            startRMSThreshold: 0.02,
            endRMSThreshold: 0.01,
            minSpeechMs: 100,
            minSilenceMs: 200
        )
        let state = vad.makeState()
        // 100ms of "speech" (high RMS)
        let speechFrame = AudioFrame(samples: Array(repeating: Float(0.1), count: 1600), sampleRate: 16000, timestamp: 0)
        let silenceFrame = AudioFrame(samples: Array(repeating: Float(0.001), count: 1600), sampleRate: 16000, timestamp: 0)

        var saw: [VoiceActivityDetector.Event] = []
        // Two speech frames (200ms) to cross min threshold.
        saw.append(contentsOf: vad.ingest(speechFrame, state: state))
        saw.append(contentsOf: vad.ingest(speechFrame, state: state))
        XCTAssertTrue(saw.contains(.speechStart))

        // Three silence frames (300ms) to cross min silence.
        var endingSaw: [VoiceActivityDetector.Event] = []
        endingSaw.append(contentsOf: vad.ingest(silenceFrame, state: state))
        endingSaw.append(contentsOf: vad.ingest(silenceFrame, state: state))
        endingSaw.append(contentsOf: vad.ingest(silenceFrame, state: state))
        XCTAssertTrue(endingSaw.contains(.speechEnd))
    }

    func test_briefSpike_doesNotTriggerSpeechStart() {
        let vad = VoiceActivityDetector(
            startRMSThreshold: 0.02,
            endRMSThreshold: 0.01,
            minSpeechMs: 200,
            minSilenceMs: 200
        )
        let state = vad.makeState()
        // Single 100ms spike, then silence — shouldn't trigger speechStart.
        let spike = AudioFrame(samples: Array(repeating: Float(0.1), count: 1600), sampleRate: 16000, timestamp: 0)
        let silence = AudioFrame(samples: Array(repeating: Float(0.001), count: 1600), sampleRate: 16000, timestamp: 0)

        var saw: [VoiceActivityDetector.Event] = []
        saw.append(contentsOf: vad.ingest(spike, state: state))
        saw.append(contentsOf: vad.ingest(silence, state: state))
        XCTAssertFalse(saw.contains(.speechStart))
    }
}
