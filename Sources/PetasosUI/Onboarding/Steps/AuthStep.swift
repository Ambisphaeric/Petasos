import SwiftUI

struct AuthStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authenticate")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if case .auth(let url) = state.step {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(url.absoluteString)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Target server \(url.absoluteString)")
            }

            Text("Petasos needs a bearer token to call the hermes API. This is whatever you set as API_SERVER_KEY when starting hermes.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SecureField("Bearer token", text: $state.bearerToken)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Bearer token")
                    .accessibilityHint("Your hermes API_SERVER_KEY value.")
                    .onSubmit(state.submitBearer)
            }

            Toggle("Remember this token in macOS Keychain", isOn: $state.rememberInKeychain)
                .accessibilityHint("Saves your bearer token securely so you don't have to re-enter it.")

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue", action: state.submitBearer)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(state.bearerToken.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .task(id: state.step) {
            if case .probe = state.step {
                await state.runProbe()
            }
        }
    }
}
