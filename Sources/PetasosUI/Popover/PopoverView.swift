import SwiftUI
import PetasosCore

public struct PopoverView: View {
    @ObservedObject private var viewModel: PopoverViewModel

    public init(viewModel: PopoverViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 380, height: 520)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Petasos")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.profile == nil ? "circle.dotted" : "circle.fill")
                .foregroundStyle(viewModel.profile == nil ? Color.secondary : Color.green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Petasos")
                    .font(.headline)
                if let profile = viewModel.profile {
                    Text(profile.nickname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Menu {
                if viewModel.session != nil {
                    Button("New conversation") { viewModel.clearSession() }
                    Divider()
                }
                Button("Settings…") { viewModel.openSettings() }
                Divider()
                Button("Quit Petasos") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.profile == nil {
            unconnectedView
                .padding(16)
        } else if let session = viewModel.session {
            ChatView(session: session, voice: viewModel.voice)
        } else {
            VStack {
                Spacer()
                ProgressView().controlSize(.regular)
                Text("Preparing chat…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var unconnectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Not connected")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Petasos needs to connect to a hermes-agent server before you can chat. The wizard takes about 30 seconds.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Set up Petasos") {
                viewModel.openOnboarding()
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }
}

@MainActor
public final class PopoverViewModel: ObservableObject {
    @Published public var profile: ServerProfile?
    @Published public var session: ChatSession?
    @Published public var voice: VoiceController?
    @Published public var lastError: String?

    public var openOnboardingAction: () -> Void = {}
    public var openSettingsAction: () -> Void = {}
    public var clearSessionAction: () -> Void = {}

    public init() {}

    public func openOnboarding() { openOnboardingAction() }
    public func openSettings() { openSettingsAction() }
    public func clearSession() { clearSessionAction() }
}
