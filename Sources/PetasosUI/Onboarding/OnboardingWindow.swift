import SwiftUI
import PetasosCore

public struct OnboardingWindow: View {
    @ObservedObject private var state: OnboardingState
    @EnvironmentObject private var flags: SystemAccessibilityFlags

    public init(state: OnboardingState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .padding(24)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 560, height: 460)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Petasos onboarding")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 22, weight: .regular))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Petasos")
                    .font(.title2.weight(.semibold))
                Text("Connect to a hermes-agent server")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stepIndicator
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepIndicator: some View {
        let indices: [Int]
        switch state.step {
        case .welcome: indices = [0]
        case .serverConfig: indices = [0, 1]
        case .auth: indices = [0, 1, 2]
        case .probe: indices = [0, 1, 2, 3]
        case .complete: indices = [0, 1, 2, 3, 4]
        }
        return HStack(spacing: 4) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(indices.contains(i) ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Step \(indices.count) of 5")
    }

    @ViewBuilder
    private var content: some View {
        switch state.step {
        case .welcome:
            WelcomeStep(state: state)
        case .serverConfig:
            ServerConfigStep(state: state)
        case .auth:
            AuthStep(state: state)
        case .probe:
            ProbeStep(state: state)
        case .complete(let profile):
            CompleteStep(profile: profile)
        }
    }

    private var footer: some View {
        HStack {
            if case .welcome = state.step {
                EmptyView()
            } else if case .complete = state.step {
                EmptyView()
            } else {
                Button("Back", action: state.goBack)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Return to the previous step.")
            }
            Spacer()
            if let err = state.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(err)")
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
