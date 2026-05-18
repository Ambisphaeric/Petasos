import SwiftUI
import PetasosCore
import PetasosSpeech

struct SpeechPane: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var draft: SpeechPreferences = .default
    @State private var sttModels: [HuggingFaceCacheScanner.InstalledModel] = []
    @State private var ttsModels: [HuggingFaceCacheScanner.InstalledModel] = []
    @State private var isPreviewing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                conversationSection
                Divider()
                sttSection
                Divider()
                ttsSection
                if draft.sttMode == .httpSidecar || draft.ttsMode == .httpSidecar {
                    Divider()
                    httpSection
                }
                Divider()
                storageSection
            }
            .padding(20)
        }
        .onAppear {
            draft = viewModel.speechPreferences
            refreshCache()
        }
        .onChange(of: draft) { _, new in
            viewModel.saveSpeechAction(new)
        }
    }

    // MARK: - Conversation (input mode + response suffix)

    @ViewBuilder
    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversation")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("Input mode", selection: $draft.inputMode) {
                Text("Click to start / stop").tag(SpeechPreferences.InputMode.clickToggle)
                Text("Push-to-talk (hold hotkey)").tag(SpeechPreferences.InputMode.pushToTalk)
                Text("Always listening (VAD)").tag(SpeechPreferences.InputMode.alwaysOn)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("Voice input mode")

            if draft.inputMode == .pushToTalk {
                HStack {
                    Text("Hotkey").frame(width: 70, alignment: .leading)
                    HotkeyRecorder(combo: $draft.pushToTalkHotkey)
                    Spacer()
                }
                Text("Hold the combo from anywhere on macOS. Release to send. The mic button still works as a fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if draft.inputMode == .alwaysOn {
                Text("Petasos listens whenever the chat is open and segments speech automatically. Each utterance is sent as soon as you pause.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Mic cooldown after TTS").frame(width: 160, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(draft.ttsTailGateMs) },
                            set: { draft.ttsTailGateMs = Int($0) }
                        ),
                        in: 0...1500,
                        step: 50
                    ) {
                        Text("TTS tail gate")
                    }
                    Text("\(draft.ttsTailGateMs) ms")
                        .font(.caption.monospacedDigit())
                        .frame(width: 60, alignment: .trailing)
                }
                Text("How long to keep the mic muted after Kokoro stops talking. Bump up if you hear the assistant transcribing itself; drop down if you have to wait too long before speaking again. Built-in MacBook speakers ≈ 400 ms; loud external speakers in a reverberant room may need 700–1000 ms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().padding(.vertical, 4)

            Toggle("Append instruction to every message", isOn: $draft.appendInstructionSuffix)
                .accessibilityHint("Adds a short instruction to each outgoing message so the assistant keeps replies concise.")

            if draft.appendInstructionSuffix {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instruction text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.instructionSuffix)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 100)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
                        .accessibilityLabel("Instruction suffix")
                    Text("Appended to each user message before it reaches Hermes. Your transcript still shows just what you said.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - STT

    @ViewBuilder
    private var sttSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STT — Speech to Text")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("Backend", selection: $draft.sttMode) {
                Text("On-device (MLX, recommended)").tag(SpeechPreferences.Mode.onDeviceMLX)
                Text("HTTP sidecar").tag(SpeechPreferences.Mode.httpSidecar)
                Text("Disabled").tag(SpeechPreferences.Mode.disabled)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("STT backend")

            if draft.sttMode == .onDeviceMLX {
                HStack {
                    Text("Model").frame(width: 70, alignment: .leading)
                    Picker("STT model", selection: $draft.sttModelID) {
                        ForEach(sttModels) { m in
                            Text(m.displayName).tag(m.id)
                        }
                        if !sttModels.contains(where: { $0.id == draft.sttModelID }) {
                            Text("\(draft.sttModelID) (not in cache)").tag(draft.sttModelID)
                        }
                    }
                    .labelsHidden()
                }
                if sttModels.isEmpty {
                    Text("No Parakeet models found in HF cache. The selected one will download on first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - TTS

    @ViewBuilder
    private var ttsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TTS — Text to Speech")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("Backend", selection: $draft.ttsMode) {
                Text("On-device (MLX, recommended)").tag(SpeechPreferences.Mode.onDeviceMLX)
                Text("HTTP sidecar").tag(SpeechPreferences.Mode.httpSidecar)
                Text("Disabled").tag(SpeechPreferences.Mode.disabled)
            }
            .pickerStyle(.radioGroup)
            .accessibilityLabel("TTS backend")

            if draft.ttsMode != .disabled {
                HStack {
                    Text("Model").frame(width: 70, alignment: .leading)
                    Picker("TTS model", selection: $draft.ttsModelID) {
                        ForEach(ttsModels) { m in
                            Text(m.displayName).tag(m.id)
                        }
                        if !ttsModels.contains(where: { $0.id == draft.ttsModelID }) {
                            Text("\(draft.ttsModelID) (not in cache)").tag(draft.ttsModelID)
                        }
                    }
                    .labelsHidden()
                }

                HStack {
                    Text("Voice").frame(width: 70, alignment: .leading)
                    Picker("Voice", selection: $draft.ttsVoiceID) {
                        ForEach(Self.kokoroVoiceList, id: \.id) { v in
                            Text(v.label).tag(v.id)
                        }
                    }
                    .labelsHidden()
                    Button {
                        Task {
                            isPreviewing = true
                            defer { isPreviewing = false }
                            await viewModel.previewVoiceAction(draft)
                        }
                    } label: {
                        Image(systemName: isPreviewing ? "stop.circle" : "play.circle")
                    }
                    .help("Preview the selected voice")
                    .accessibilityLabel("Preview voice")
                }

                HStack {
                    Text("Rate").frame(width: 70, alignment: .leading)
                    Slider(value: $draft.ttsSpeakingRate, in: 0.5...1.5, step: 0.05) {
                        Text("Speaking rate")
                    }
                    Text(String(format: "%.2fx", draft.ttsSpeakingRate))
                        .font(.caption.monospacedDigit())
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - HTTP sidecar config (shown only when at least one role uses it)

    @ViewBuilder
    private var httpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HTTP sidecar")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if draft.sttMode == .httpSidecar {
                HStack {
                    Text("STT URL").frame(width: 70, alignment: .leading)
                    TextField("http://localhost:8001", text: $draft.httpSTTURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("HTTP STT URL")
                }
            }
            if draft.ttsMode == .httpSidecar {
                HStack {
                    Text("TTS URL").frame(width: 70, alignment: .leading)
                    TextField("http://localhost:8002", text: $draft.httpTTSURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("HTTP TTS URL")
                }
            }
            Toggle("Reuse hermes bearer for HTTP auth", isOn: $draft.reuseHermesBearerForHTTP)
                .accessibilityHint("Sends your hermes API key to the local speech sidecar so it can require auth too.")
        }
    }

    // MARK: - Storage

    @ViewBuilder
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model storage")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            let total = (sttModels + ttsModels).reduce(Int64(0)) { $0 + $1.sizeBytes }
            Text(verbatim: "~/.cache/huggingface/hub")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(sttModels.count + ttsModels.count) detected models · \(formatBytes(total)) used")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Refresh") { refreshCache() }
                Button("Open in Finder") {
                    let url = URL(fileURLWithPath: NSString(string: "~/.cache/huggingface/hub").expandingTildeInPath)
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func refreshCache() {
        let scanner = HuggingFaceCacheScanner()
        sttModels = scanner.scan(matching: "mlx-community/parakeet-*")
        ttsModels = scanner.scan(matching: "mlx-community/Kokoro-*")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private struct VoiceEntry: Identifiable {
        let id: String
        let label: String
    }

    private static let kokoroVoiceList: [VoiceEntry] = {
        let voices: [(String, String, String)] = [
            ("af_bella", "Bella", "US female"),
            ("af_heart", "Heart", "US female"),
            ("af_nicole", "Nicole", "US female"),
            ("af_sarah", "Sarah", "US female"),
            ("af_sky", "Sky", "US female"),
            ("am_adam", "Adam", "US male"),
            ("am_michael", "Michael", "US male"),
            ("am_onyx", "Onyx", "US male"),
            ("bf_emma", "Emma", "UK female"),
            ("bf_isabella", "Isabella", "UK female"),
            ("bm_george", "George", "UK male"),
            ("ef_dora", "Dora", "Spanish"),
            ("ff_siwis", "Siwis", "French"),
            ("hf_alpha", "Alpha", "Hindi"),
            ("if_sara", "Sara", "Italian"),
            ("jf_alpha", "Alpha", "Japanese"),
            ("pf_dora", "Dora", "Portuguese"),
            ("zf_xiaobei", "Xiaobei", "Chinese"),
        ]
        return voices.map { VoiceEntry(id: $0.0, label: "\($0.1) (\($0.2))") }
    }()
}
