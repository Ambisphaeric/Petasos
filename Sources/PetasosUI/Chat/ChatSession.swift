import Foundation
import PetasosCore
import PetasosHermes

/// State machine that turns user input + hermes run events into a transcript.
/// One ChatSession per "conversation"; the menu bar popover owns one.
@MainActor
public final class ChatSession: ObservableObject {
    public enum Status: Sendable, Equatable {
        case idle
        case sending
        case streaming
        case awaitingApproval
        case error(String)
    }

    @Published public private(set) var turns: [ChatTurn] = []
    @Published public private(set) var status: Status = .idle
    @Published public private(set) var currentStreamingText: String = ""
    @Published public private(set) var toolProgress: RunEvent.ToolProgress?
    @Published public private(set) var pendingApproval: RunEvent.ApprovalRequest?
    @Published public private(set) var lastError: String?

    public let conversationName: String

    /// Hooks for the voice/TTS layer. Set by AppEnvironment when constructing this
    /// session. Closures run on the MainActor (same as ChatSession itself).
    public var onAssistantStart: (() -> Void)?
    public var onAssistantDelta: ((String) -> Void)?
    public var onAssistantEnd: (() -> Void)?

    /// Optional text appended to every outgoing user message before it hits the
    /// server. The user's own bubble in the transcript still shows the bare
    /// message — only the payload to Hermes carries the suffix. Used by the
    /// "Conversation" preference to enforce concise replies regardless of how
    /// long the user yaps.
    public var inputSuffix: String?

    private let endpoint: RunsEndpoint
    private var streamingTask: Task<Void, Never>?
    private var currentRunID: String?
    private var assistantTurnID: UUID?
    private var assistantStartFired = false

    public init(endpoint: RunsEndpoint, conversationName: String = "petasos-default") {
        self.endpoint = endpoint
        self.conversationName = conversationName
    }

    public var isBusy: Bool {
        switch status {
        case .sending, .streaming, .awaitingApproval: return true
        case .idle, .error: return false
        }
    }

    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If a previous run is in flight, cancel it before starting a new one.
        if isBusy { cancel() }

        let userTurn = ChatTurn(role: .user, text: trimmed)
        turns.append(userTurn)

        let assistant = ChatTurn(role: .assistant, text: "")
        turns.append(assistant)
        assistantTurnID = assistant.id

        status = .sending
        currentStreamingText = ""
        toolProgress = nil
        lastError = nil
        assistantStartFired = false

        let payload: String = {
            if let suffix = inputSuffix?.trimmingCharacters(in: .whitespacesAndNewlines),
               !suffix.isEmpty {
                return trimmed + "\n\n" + suffix
            }
            return trimmed
        }()

        do {
            let handle = try await endpoint.submit(RunSubmission(
                input: payload,
                conversation: conversationName
            ))
            currentRunID = handle.runID
            await streamEvents(runID: handle.runID)
        } catch {
            handle(error: error)
        }
    }

    public func cancel() {
        streamingTask?.cancel()
        streamingTask = nil
        if let id = currentRunID {
            let endpoint = self.endpoint
            Task.detached { try? await endpoint.stop(runID: id) }
        }
        currentRunID = nil
        // Drop the empty assistant placeholder if cancelled before any text arrived.
        if let id = assistantTurnID,
           let idx = turns.firstIndex(where: { $0.id == id }),
           turns[idx].text.isEmpty {
            turns.remove(at: idx)
        }
        assistantTurnID = nil
        if case .error = status {
            // keep error
        } else {
            status = .idle
        }
    }

    public func clear() {
        cancel()
        turns.removeAll()
        currentStreamingText = ""
        toolProgress = nil
        pendingApproval = nil
        lastError = nil
    }

    // MARK: - Streaming

    private func streamEvents(runID: String) async {
        status = .streaming
        let stream = RunEventStream.subscribe(runID: runID, endpoint: endpoint)
        let task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard !Task.isCancelled else { break }
                    await self?.handle(event: event)
                }
                await self?.streamFinished()
            } catch {
                await self?.handle(error: error)
            }
        }
        streamingTask = task
        await task.value
    }

    private func handle(event: RunEvent) {
        switch event {
        case .runCreated:
            break

        case .textDelta(let text):
            if !assistantStartFired {
                assistantStartFired = true
                onAssistantStart?()
            }
            currentStreamingText += text
            appendToAssistant(text)
            onAssistantDelta?(text)

        case .reasoningAvailable(let authoritative):
            // The server's authoritative version of the final assistant message.
            // If our streamed buffer is empty or somehow drifted, snap to this.
            if let id = assistantTurnID,
               let idx = turns.firstIndex(where: { $0.id == id }),
               turns[idx].text.isEmpty,
               !authoritative.isEmpty {
                turns[idx].text = authoritative
            }

        case .itemAdded, .itemDone, .unknown:
            // P1 ignores structured item events; P3 may surface them as visible turns.
            break

        case .toolProgress(let p):
            toolProgress = p

        case .approvalRequested(let req):
            pendingApproval = req
            status = .awaitingApproval

        case .completed(let finalText, _):
            // Fill in from the final consolidated output if streaming produced nothing.
            if let final = finalText,
               let id = assistantTurnID,
               let idx = turns.firstIndex(where: { $0.id == id }),
               turns[idx].text.isEmpty {
                turns[idx].text = final
                // No deltas fired during the run — emit the whole thing once so TTS can speak it.
                if !assistantStartFired {
                    assistantStartFired = true
                    onAssistantStart?()
                    onAssistantDelta?(final)
                }
            }
            if assistantStartFired { onAssistantEnd?() }
            assistantStartFired = false
            toolProgress = nil
            currentRunID = nil
            assistantTurnID = nil
            currentStreamingText = ""
            status = .idle

        case .error(let msg):
            handle(error: HermesError.server(status: 0, message: msg))
        }
    }

    private func appendToAssistant(_ text: String) {
        guard let id = assistantTurnID,
              let idx = turns.firstIndex(where: { $0.id == id }) else { return }
        turns[idx].text += text
    }

    private func streamFinished() {
        // Stream closed cleanly without an explicit .completed event.
        if case .streaming = status {
            status = .idle
            currentRunID = nil
            toolProgress = nil
            assistantTurnID = nil
        }
    }

    private func handle(error: Error) {
        let msg = (error as? HermesError)?.errorDescription ?? error.localizedDescription
        lastError = msg
        status = .error(msg)
        if let id = assistantTurnID,
           let idx = turns.firstIndex(where: { $0.id == id }),
           turns[idx].text.isEmpty {
            turns.remove(at: idx)
        }
        assistantTurnID = nil
        currentRunID = nil
    }
}
