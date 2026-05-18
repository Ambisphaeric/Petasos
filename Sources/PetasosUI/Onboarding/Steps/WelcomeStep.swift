import SwiftUI

struct WelcomeStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text("Petasos is an accessibility-first menu bar companion for hermes-agent. Before we begin, we need to connect to a running hermes-agent server.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Quickly: if hermes is running on this Mac, Petasos will find it automatically. Otherwise you can point it at any reachable hermes URL (LAN, VPN, or remote).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    state.step = .serverConfig
                    Task { await state.startDiscovery() }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .accessibilityHint("Begin searching for hermes-agent servers.")
            }
        }
    }
}
