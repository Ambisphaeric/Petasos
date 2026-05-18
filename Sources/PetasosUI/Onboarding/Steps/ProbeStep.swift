import SwiftUI
import PetasosCore

struct ProbeStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verify connection")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            if state.probeInFlight {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Probing hermes capabilities and model list…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Verifying connection…")
            } else if let result = state.probeResult {
                capabilitiesSummary(result.capabilities)
                modelPicker(result.models)
                if let detailed = result.detailedHealth {
                    healthSummary(detailed)
                }
            } else if state.errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Retry") { Task { await state.runProbe() } }
                    .keyboardShortcut(.defaultAction)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Save and continue") {
                    state.finalize(keychainAccount: KeychainAccount.default)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(state.probeResult == nil)
            }
        }
        .task {
            if state.probeResult == nil, state.errorMessage == nil {
                await state.runProbe()
            }
        }
    }

    @ViewBuilder
    private func capabilitiesSummary(_ caps: Capabilities) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Connected to \(caps.platform)").font(.callout.weight(.medium))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connected to \(caps.platform).")

            let supported = [
                caps.features.chatCompletionsStreaming == true ? "chat streaming" : nil,
                caps.features.responsesStreaming == true ? "responses streaming" : nil,
                caps.features.runEventsSse ? "run events" : nil,
                caps.features.toolProgressEvents == true ? "tool progress" : nil,
                caps.features.runApprovalResponse == true ? "approval prompts" : nil,
            ].compactMap { $0 }
            if !supported.isEmpty {
                Text("Supports: \(supported.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func modelPicker(_ models: [HermesModel]) -> some View {
        if !models.isEmpty {
            HStack {
                Text("Model")
                    .frame(width: 60, alignment: .leading)
                Picker("Model", selection: Binding(
                    get: { state.selectedModelID ?? models.first?.id ?? "" },
                    set: { state.selectedModelID = $0 }
                )) {
                    ForEach(models) { m in
                        Text(m.id).tag(m.id)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Preferred model")
            }
        }
    }

    @ViewBuilder
    private func healthSummary(_ detailed: DetailedHealth) -> some View {
        if let platforms = detailed.platforms, !platforms.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gateway integrations")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                ForEach(platforms.sorted(by: { $0.key < $1.key }), id: \.key) { name, p in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(p.state == "connected" ? Color.green : (p.state == "fatal" ? Color.red : Color.orange))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(name).font(.caption)
                        Text("·").font(.caption).foregroundStyle(.secondary)
                        Text(p.state).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(name): \(p.state)")
                }
            }
        }
    }
}
