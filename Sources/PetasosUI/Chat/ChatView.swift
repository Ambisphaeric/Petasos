import SwiftUI
import PetasosCore

public struct ChatView: View {
    @ObservedObject var session: ChatSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @State private var input: String = ""

    var voice: VoiceController?

    public init(session: ChatSession, voice: VoiceController? = nil) {
        self.session = session
        self.voice = voice
    }

    public var body: some View {
        VStack(spacing: 0) {
            transcript
            statusStrip
            if let voice {
                Divider()
                VoiceControlBar(voice: voice)
            }
            Divider()
            inputBar
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chat with hermes")
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Sentinel anchor at the top of the content — used to
                    // reset the scroll position when the transcript is cleared.
                    Color.clear
                        .frame(height: 0)
                        .id(Self.topAnchorID)
                    if session.turns.isEmpty {
                        emptyState
                    } else {
                        ForEach(session.turns) { turn in
                            TurnView(turn: turn)
                                .id(turn.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.turns.last?.text) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: session.turns.count) { old, new in
                if new == 0 {
                    // Cleared: reset to top so the empty state is visible.
                    // Without this, ScrollView keeps the previous content
                    // offset, leaving the (now small) empty state scrolled off.
                    scrollToTop(proxy: proxy, animated: old > 0)
                } else {
                    scrollToBottom(proxy: proxy)
                }
            }
            .accessibilityLabel("Chat transcript")
        }
    }

    private static let topAnchorID = "petasos.chat.top"

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastID = session.turns.last?.id else { return }
        let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.18)
        withAnimation(animation) {
            proxy.scrollTo(lastID, anchor: .bottom)
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy, animated: Bool) {
        let animation: Animation? = (animated && !reduceMotion) ? .easeOut(duration: 0.18) : nil
        withAnimation(animation) {
            proxy.scrollTo(Self.topAnchorID, anchor: .top)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New conversation")
                .font(.headline)
            Text("Type below and press Return to send. Press ⌘. to stop a streaming reply.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Status strip (live region for tool progress + errors)

    @ViewBuilder
    private var statusStrip: some View {
        if let progress = session.toolProgress {
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(toolProgressLabel(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.08))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(toolProgressAccessibilityLabel(progress))
            .accessibilityAddTraits(.updatesFrequently)
            .onChange(of: session.toolProgress) { _, new in
                if let new {
                    StatusAnnouncer.announce(toolProgressAccessibilityLabel(new), priority: .low)
                }
            }
        } else if let err = session.lastError {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.08))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(err)")
            .onChange(of: session.lastError) { _, new in
                if let new {
                    StatusAnnouncer.announce("Error: \(new)", priority: .high)
                }
            }
        }
    }

    private func toolProgressLabel(_ p: RunEvent.ToolProgress) -> String {
        let phase = p.phase ?? "running"
        return "Tool · \(p.toolName) · \(phase)"
    }

    private func toolProgressAccessibilityLabel(_ p: RunEvent.ToolProgress) -> String {
        if let phase = p.phase {
            return "Hermes is \(phase) the \(p.toolName) tool."
        }
        return "Hermes is using the \(p.toolName) tool."
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask Hermes…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .onSubmit(submit)
                .accessibilityLabel("Message input")
                .accessibilityHint("Type your message and press return to send.")
            if session.isBusy {
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .keyboardShortcut(".", modifiers: [.command])
                .accessibilityLabel("Stop streaming")
                .accessibilityHint("Cancel the in-progress reply.")
            } else {
                Button {
                    submit()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send message")
            }
        }
        .padding(8)
        .background(.bar)
        .task { inputFocused = true }
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let copy = text
        input = ""
        Task { await session.send(copy) }
    }
}

// MARK: - Turn view

private struct TurnView: View {
    let turn: ChatTurn

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            roleBadge
            VStack(alignment: .leading, spacing: 2) {
                roleLabel
                Text(turn.text.isEmpty ? "…" : turn.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(turn.role == .assistant ? .updatesFrequently : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var roleBadge: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
            .frame(width: 18, alignment: .center)
            .accessibilityHidden(true)
    }

    private var roleLabel: some View {
        Text(roleDisplayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var iconName: String {
        switch turn.role {
        case .user: return "person.circle.fill"
        case .assistant: return "circle.hexagongrid.fill"
        case .system: return "info.circle"
        case .tool: return "wrench.adjustable.fill"
        }
    }

    private var iconColor: Color {
        switch turn.role {
        case .user: return .blue
        case .assistant: return .green
        case .system: return .secondary
        case .tool: return .orange
        }
    }

    private var roleDisplayName: String {
        switch turn.role {
        case .user: return "You"
        case .assistant: return "Hermes"
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    private var accessibilityLabel: String {
        "\(roleDisplayName) said: \(turn.text)"
    }
}
