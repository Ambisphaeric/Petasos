import SwiftUI
import PetasosSpeech

/// Compact voice-control strip placed above the chat input bar.
///
/// Shows:
///   - A microphone button (idle / listening / processing)
///   - The live STT transcript while speaking
///   - A "Speak replies" toggle
public struct VoiceControlBar: View {
    @ObservedObject var voice: VoiceController

    public init(voice: VoiceController) {
        self.voice = voice
    }

    public var body: some View {
        HStack(spacing: 10) {
            micButton
            transcriptOrPrompt
            Spacer()
            ttsToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar.opacity(0.4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice controls")
    }

    @ViewBuilder
    private var micButton: some View {
        let listening = voice.isListening
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: listening ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(listening ? Color.red : Color.accentColor)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(!voice.isAvailable)
        .help(voice.isAvailable ? (listening ? "Stop and send (⌘⇧ space)" : "Start speaking (⌘⇧ space)") : "Configure speech in Settings")
        .accessibilityLabel(listening ? "Stop speaking and send" : "Start speaking")
        .accessibilityHint(voice.isAvailable ? "Toggles voice input." : "Speech not configured. Open Settings to choose a backend.")
        .keyboardShortcut("v", modifiers: [.command, .shift])
    }

    @ViewBuilder
    private var transcriptOrPrompt: some View {
        switch voice.sttStatus {
        case .listening:
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(voice.liveTranscript.isEmpty ? "Listening…" : voice.liveTranscript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Listening. Live transcript: \(voice.liveTranscript)")
            .accessibilityAddTraits(.updatesFrequently)

        case .starting, .finalizing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Working…").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .accessibilityLabel("Speech error: \(msg)")

        case .idle:
            if !voice.isAvailable {
                Text("Voice not configured")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .speaking = voice.ttsStatus {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Speaking reply…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                EmptyView()
            }
        }
    }

    private var ttsToggle: some View {
        Toggle(isOn: $voice.speakResponses) {
            Image(systemName: voice.speakResponses ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.caption)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .accessibilityLabel(voice.speakResponses ? "Speak replies enabled" : "Speak replies disabled")
        .accessibilityHint("Toggles spoken responses.")
        .disabled(voice.ttsPlayer == nil)
    }

    private func toggle() async {
        if voice.isListening {
            await voice.stopListeningAndSend()
        } else {
            await voice.startListening()
        }
    }
}
