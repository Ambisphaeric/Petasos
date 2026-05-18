import SwiftUI

struct ServerConfigStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find your hermes-agent server")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if state.isDiscovering {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking for hermes on this Mac…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if !state.candidates.isEmpty {
                Text("Found nearby:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(state.candidates) { candidate in
                        Button {
                            state.pick(candidate: candidate)
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.url.absoluteString)
                                        .font(.system(.body, design: .monospaced))
                                    if let platform = candidate.platform {
                                        Text(platform)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use server at \(candidate.url.absoluteString)")
                        .accessibilityHint("Selects this server and moves to authentication.")
                    }
                }
            } else {
                Text("No local hermes-agent found.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.vertical, 4)

            Text("Or enter a URL manually:")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("http://hermes_ip:8642", text: $state.manualURLString)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Hermes server URL")
                    .accessibilityHint("Enter the URL of your hermes-agent server.")
                    .onSubmit(state.confirmManualURL)
                Button("Use this URL", action: state.confirmManualURL)
                    .disabled(state.manualURLString.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
