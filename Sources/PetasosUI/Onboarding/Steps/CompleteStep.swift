import SwiftUI
import PetasosCore

struct CompleteStep: View {
    let profile: ServerProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("You're set up")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }

            Text("Connected to \(profile.nickname) and credentials are stored in macOS Keychain.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("What's next:")
                    .font(.callout.weight(.medium))
                Text("Click the Petasos icon in the menu bar to open chat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Voice (P2), overlays (P3), and shorthand expansion (P4) are coming.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
    }
}
