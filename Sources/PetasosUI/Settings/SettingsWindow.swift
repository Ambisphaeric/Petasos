import SwiftUI
import PetasosCore
import PetasosSpeech

public struct SettingsWindow: View {
    @ObservedObject private var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            ServerPane(viewModel: viewModel)
                .tabItem { Label("Server", systemImage: "server.rack") }
                .accessibilityLabel("Server settings")
            SpeechPane(viewModel: viewModel)
                .tabItem { Label("Speech", systemImage: "waveform") }
                .accessibilityLabel("Speech settings")
            AccessibilityPane(viewModel: viewModel)
                .tabItem { Label("Accessibility", systemImage: "accessibility") }
                .accessibilityLabel("Accessibility settings")
            DiagnosticsPane(viewModel: viewModel)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .accessibilityLabel("Diagnostics")
        }
        .frame(width: 600, height: 520)
    }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var profile: ServerProfile?
    @Published public var accessibilityProfile: AccessibilityProfile = .standard
    @Published public var detailedHealth: DetailedHealth?
    @Published public var speechPreferences: SpeechPreferences = .default

    public var reonboardAction: () -> Void = {}
    public var refreshHealthAction: () async -> Void = {}
    public var saveAccessibilityAction: (AccessibilityProfile) -> Void = { _ in }
    public var saveSpeechAction: (SpeechPreferences) -> Void = { _ in }
    public var previewVoiceAction: (SpeechPreferences) async -> Void = { _ in }

    public init() {}
}

private struct ServerPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if let profile = viewModel.profile {
                Section {
                    LabeledContent("Nickname", value: profile.nickname)
                    LabeledContent("URL", value: profile.baseURL.absoluteString)
                    if let model = profile.preferredModel {
                        LabeledContent("Model", value: model)
                    }
                    if let last = profile.lastVerifiedAt {
                        LabeledContent("Last verified", value: last.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section {
                    Button("Reconnect / change server", action: viewModel.reonboardAction)
                }
            } else {
                Section {
                    Text("No server configured.")
                        .foregroundStyle(.secondary)
                    Button("Run setup wizard", action: viewModel.reonboardAction)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
    }
}

private struct AccessibilityPane: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var draft: AccessibilityProfile = .standard

    var body: some View {
        Form {
            Section("Profile") {
                Picker("Profile", selection: Binding(
                    get: { draft.enforceHighContrast ? "accessibility" : "standard" },
                    set: { sel in
                        draft = (sel == "accessibility") ? .accessibility : .standard
                        viewModel.saveAccessibilityAction(draft)
                    }
                )) {
                    Text("Standard").tag("standard")
                    Text("Accessibility (high contrast, large type)").tag("accessibility")
                }
                .pickerStyle(.radioGroup)
            }
            Section("Behavior") {
                Toggle("Respect system Reduce Motion", isOn: $draft.respectReduceMotion)
                Toggle("Respect system Reduce Transparency", isOn: $draft.respectReduceTransparency)
                Toggle("Respect system Increase Contrast", isOn: $draft.respectIncreaseContrast)
                Toggle("Announce state changes via TTS", isOn: $draft.announceStateChanges)
            }
        }
        .padding(20)
        .onAppear { draft = viewModel.accessibilityProfile }
        .onChange(of: draft) { _, new in
            viewModel.saveAccessibilityAction(new)
        }
    }
}

private struct DiagnosticsPane: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Server health")
                    .font(.headline)
                Spacer()
                Button("Refresh") { Task { await viewModel.refreshHealthAction() } }
            }
            if let h = viewModel.detailedHealth {
                LabeledContent("Status", value: h.status)
                if let g = h.gatewayState { LabeledContent("Gateway", value: g) }
                if let p = h.pid.map(String.init) { LabeledContent("Server PID", value: p) }
                if let agents = h.activeAgents { LabeledContent("Active agents", value: String(agents)) }
                if let platforms = h.platforms {
                    Divider()
                    ForEach(platforms.sorted(by: { $0.key < $1.key }), id: \.key) { name, p in
                        HStack {
                            Circle()
                                .fill(p.state == "connected" ? Color.green : (p.state == "fatal" ? Color.red : Color.orange))
                                .frame(width: 8, height: 8)
                            Text(name)
                            Spacer()
                            Text(p.state).foregroundStyle(.secondary)
                            if let err = p.errorMessage {
                                Text("(\(err))").font(.caption).foregroundStyle(.red)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Text("Click Refresh to fetch health from the server.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }
}
