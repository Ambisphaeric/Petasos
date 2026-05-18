import AppKit
import SwiftUI
import PetasosCore
import PetasosHermes
import PetasosSpeech
import PetasosSpeechHTTP
import PetasosSpeechMLX
import PetasosUI

/// Dependency container + window coordinator.
/// One instance is created at launch and owns all long-lived state.
@MainActor
final class AppEnvironment: ObservableObject {
    let credentials: CredentialStore
    let profileStore: ProfileStore
    let systemFlags: SystemAccessibilityFlags
    let speechPreferences: SpeechPreferencesStore
    let popoverVM: PopoverViewModel
    let settingsVM: SettingsViewModel
    let logger: AppLogger
    let hotkey = GlobalHotkey()

    /// Cached bearer for the active profile. Populated once at bootstrap and on
    /// re-onboarding so we avoid hitting SQLite on every read path.
    private var cachedBearer: String?
    private var popoverIsOpen: Bool = false

    private var onboardingState: OnboardingState?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindowDelegate: AnyWindowDelegate?
    private var settingsWindowDelegate: AnyWindowDelegate?

    private init(
        credentials: CredentialStore,
        profileStore: ProfileStore,
        systemFlags: SystemAccessibilityFlags,
        speechPreferences: SpeechPreferencesStore,
        logger: AppLogger
    ) {
        self.credentials = credentials
        self.profileStore = profileStore
        self.systemFlags = systemFlags
        self.speechPreferences = speechPreferences
        self.logger = logger
        self.popoverVM = PopoverViewModel()
        self.settingsVM = SettingsViewModel()
        self.cachedBearer = profileStore.profile.flatMap {
            try? credentials.load(account: $0.keychainAccount)
        }

        wireUpViewModels()
    }

    /// Cached read; falls back to SQLite only if the cache is empty (e.g. profile
    /// loaded after init). Call sites should use this rather than touching
    /// `credentials` directly so we don't re-open the DB on every read.
    private func currentBearer() -> String? {
        if let cachedBearer { return cachedBearer }
        guard let profile = profileStore.profile,
              let bearer = try? credentials.load(account: profile.keychainAccount) else {
            return nil
        }
        cachedBearer = bearer
        return bearer
    }

    static func bootstrap() -> AppEnvironment {
        let logger = AppLogger()
        let credentials: CredentialStore
        do {
            credentials = try CredentialStore()
        } catch {
            logger.error("Credential store init failed: \(error). Falling back to in-memory store.")
            // Last-ditch fallback so the app at least launches. The user will be
            // re-onboarded and the in-memory bearer will be lost on quit.
            credentials = try! CredentialStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Petasos-fallback"))
        }
        let profileStore = ProfileStore(logger: logger)
        let flags = SystemAccessibilityFlags()
        let speechPrefs = SpeechPreferencesStore()

        // Register provider factories so the Settings picker can list them.
        HTTPSpeechRegistration.register()
        MLXSpeechRegistration.register()

        let env = AppEnvironment(
            credentials: credentials,
            profileStore: profileStore,
            systemFlags: flags,
            speechPreferences: speechPrefs,
            logger: logger
        )
        env.popoverVM.profile = profileStore.profile
        env.settingsVM.profile = profileStore.profile
        env.settingsVM.speechPreferences = speechPrefs.load()
        env.makeChatSessionIfPossible()
        env.makeVoiceControllerIfPossible()
        env.applyHotkeyRegistration()
        return env
    }

    // MARK: - View-model wiring

    private func wireUpViewModels() {
        popoverVM.openOnboardingAction = { [weak self] in self?.openOnboarding() }
        popoverVM.openSettingsAction = { [weak self] in self?.openSettings() }
        popoverVM.clearSessionAction = { [weak self] in self?.popoverVM.session?.clear() }

        settingsVM.reonboardAction = { [weak self] in self?.openOnboarding() }
        settingsVM.refreshHealthAction = { [weak self] in await self?.refreshHealth() }
        settingsVM.saveAccessibilityAction = { _ in
            // P0: in-memory only. P4 persists via UserDefaults.
        }
        settingsVM.saveSpeechAction = { [weak self] prefs in
            guard let self else { return }
            self.speechPreferences.save(prefs)
            self.settingsVM.speechPreferences = prefs
            self.makeVoiceControllerIfPossible()
            self.applyInputSuffix()
            self.applyHotkeyRegistration()
            // If we just switched into always-on while the popover is visible,
            // kick listening on immediately (and vice-versa).
            self.applyAlwaysOnIfNeeded()
        }
        settingsVM.previewVoiceAction = { [weak self] prefs in
            await self?.previewVoice(with: prefs)
        }
    }

    private func previewVoice(with prefs: SpeechPreferences) async {
        guard prefs.ttsMode != .disabled else { return }
        let bearer = currentBearer()
        let synth: any SpeechSynthesizer
        switch prefs.ttsMode {
        case .onDeviceMLX:
            synth = KokoroTTSProvider(modelRepo: prefs.ttsModelID, speakingRate: prefs.ttsSpeakingRate)
        case .httpSidecar:
            guard let url = URL(string: prefs.httpTTSURL) else { return }
            let token = prefs.reuseHermesBearerForHTTP ? bearer : nil
            synth = HTTPTTSProvider(endpointURL: url, bearer: token, speakingRate: prefs.ttsSpeakingRate)
        case .disabled: return
        }
        let player = TTSPlayer(synthesizer: synth)
        let voice = KokoroTTSProvider.kokoroVoices.first(where: { $0.id == prefs.ttsVoiceID })
            ?? HTTPTTSProvider.defaultKokoroVoices.first(where: { $0.id == prefs.ttsVoiceID })
            ?? KokoroTTSProvider.kokoroVoices.first
        player.voice = voice
        try? await player.speak("Hello, I am \(voice?.displayName ?? "Petasos").")
    }

    private func makeChatSessionIfPossible() {
        guard let profile = profileStore.profile,
              let bearer = currentBearer() else {
            popoverVM.session = nil
            return
        }
        let endpoint = RunsEndpoint(baseURL: profile.baseURL, bearerToken: bearer)
        let session = ChatSession(endpoint: endpoint)
        popoverVM.session = session
        applyInputSuffix()
    }

    /// Push the saved instruction suffix into the live ChatSession. Idempotent —
    /// safe to call any time prefs change or the session is rebuilt.
    private func applyInputSuffix() {
        let prefs = speechPreferences.load()
        popoverVM.session?.inputSuffix = (prefs.appendInstructionSuffix && !prefs.instructionSuffix.isEmpty)
            ? prefs.instructionSuffix : nil
    }

    /// Re-register the push-to-talk hotkey based on current prefs. Unregistered
    /// in modes that don't use it.
    private func applyHotkeyRegistration() {
        let prefs = speechPreferences.load()
        guard prefs.inputMode == .pushToTalk else {
            hotkey.register(combo: nil)
            return
        }
        hotkey.onKeyDown = { [weak self] in
            Task { @MainActor in await self?.handleHotkeyDown() }
        }
        hotkey.onKeyUp = { [weak self] in
            Task { @MainActor in await self?.handleHotkeyUp() }
        }
        hotkey.register(combo: prefs.pushToTalkHotkey)
    }

    private func handleHotkeyDown() async {
        guard let voice = popoverVM.voice, voice.isAvailable, !voice.isListening else { return }
        await voice.startListening()
    }

    private func handleHotkeyUp() async {
        guard let voice = popoverVM.voice, voice.isListening else { return }
        await voice.stopListeningAndSend()
    }

    /// Called when the menu bar popover transitions to shown/hidden. Drives the
    /// always-on input mode: start listening when the chat is visible, stop
    /// when it's hidden so we don't keep the mic warm in the background.
    func handlePopoverDidShow() {
        popoverIsOpen = true
        applyAlwaysOnIfNeeded()
    }

    func handlePopoverDidClose() {
        popoverIsOpen = false
        applyAlwaysOnIfNeeded()
    }

    private func applyAlwaysOnIfNeeded() {
        let prefs = speechPreferences.load()
        guard let voice = popoverVM.voice else { return }
        if prefs.inputMode == .alwaysOn && popoverIsOpen {
            if !voice.isListening {
                Task { await voice.startListening() }
            }
        } else if prefs.inputMode != .alwaysOn || !popoverIsOpen {
            // Tear down any in-flight always-on session.
            if voice.isListening, voice.startMode == .continuous {
                voice.cancelListening()
            }
        }
    }

    /// Build the active STT/TTS providers from saved SpeechPreferences and hand them to
    /// PopoverViewModel as a VoiceController. Wires the ChatSession ⇄ VoiceController
    /// callbacks so mic input flows into chat and streamed responses flow into TTS.
    private func makeVoiceControllerIfPossible() {
        let prefs = speechPreferences.load()
        let bearer = currentBearer()

        let stt: STTSession? = {
            switch prefs.sttMode {
            case .disabled: return nil
            case .onDeviceMLX:
                return STTSession(recognizer: ParakeetSTTProvider(modelRepo: prefs.sttModelID))
            case .httpSidecar:
                guard let url = URL(string: prefs.httpSTTURL) else { return nil }
                let token = prefs.reuseHermesBearerForHTTP ? bearer : nil
                return STTSession(recognizer: HTTPSTTProvider(endpointURL: url, bearer: token))
            }
        }()

        let tts: TTSPlayer? = {
            switch prefs.ttsMode {
            case .disabled: return nil
            case .onDeviceMLX:
                let synth = KokoroTTSProvider(modelRepo: prefs.ttsModelID, speakingRate: prefs.ttsSpeakingRate)
                let player = TTSPlayer(synthesizer: synth)
                player.voice = KokoroTTSProvider.kokoroVoices.first(where: { $0.id == prefs.ttsVoiceID })
                    ?? KokoroTTSProvider.kokoroVoices.first
                return player
            case .httpSidecar:
                guard let url = URL(string: prefs.httpTTSURL) else { return nil }
                let token = prefs.reuseHermesBearerForHTTP ? bearer : nil
                let synth = HTTPTTSProvider(endpointURL: url, bearer: token, speakingRate: prefs.ttsSpeakingRate)
                let player = TTSPlayer(synthesizer: synth)
                player.voice = HTTPTTSProvider.defaultKokoroVoices.first(where: { $0.id == prefs.ttsVoiceID })
                    ?? HTTPTTSProvider.defaultKokoroVoices.first
                return player
            }
        }()

        let voice = VoiceController(stt: stt, tts: tts)
        voice.startMode = (prefs.inputMode == .alwaysOn) ? .continuous : .oneShot
        voice.ttsTailGateMs = UInt64(max(0, prefs.ttsTailGateMs))
        if let session = popoverVM.session {
            voice.onUtterance = { [weak session] text in
                Task { @MainActor in await session?.send(text) }
            }
            session.onAssistantStart = { [weak voice] in
                Task { @MainActor in await voice?.beginSpeaking() }
            }
            session.onAssistantDelta = { [weak voice] delta in
                voice?.appendForSpeech(delta)
            }
            session.onAssistantEnd = { [weak voice] in
                voice?.finishSpeaking()
            }
        }
        popoverVM.voice = voice
    }

    // MARK: - Windows

    func openOnboarding() {
        if let win = onboardingWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let state = OnboardingState()
        state.onComplete = { [weak self] profile, bearer in
            self?.finalizeOnboarding(profile: profile, bearer: bearer)
        }
        self.onboardingState = state

        let hosting = NSHostingController(
            rootView: OnboardingWindow(state: state)
                .environmentObject(systemFlags)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set up Petasos"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        let delegate = AnyWindowDelegate { [weak self] in
            self?.onboardingWindow = nil
            self?.onboardingState = nil
            self?.onboardingWindowDelegate = nil
        }
        self.onboardingWindowDelegate = delegate
        window.delegate = delegate
        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openSettings() {
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: SettingsWindow(viewModel: settingsVM)
                .environmentObject(systemFlags)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Petasos Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        let delegate = AnyWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.settingsWindowDelegate = nil
        }
        self.settingsWindowDelegate = delegate
        window.delegate = delegate
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Profile lifecycle

    private func finalizeOnboarding(profile: ServerProfile, bearer: String) {
        do {
            try credentials.save(token: bearer, account: profile.keychainAccount)
            cachedBearer = bearer
            profileStore.save(profile)
            popoverVM.profile = profile
            settingsVM.profile = profile
            makeChatSessionIfPossible()
            logger.info("Onboarding complete for \(profile.nickname).")
        } catch {
            logger.error("Failed to save bearer to Keychain: \(error)")
        }
    }

    func recheck() async {
        guard let profile = profileStore.profile,
              let bearer = currentBearer() else {
            popoverVM.profile = nil
            return
        }
        let client = HermesClient(baseURL: profile.baseURL, bearerToken: bearer)
        do {
            let caps = try await client.capabilities()
            var updated = profile
            updated.lastCapabilities = caps
            updated.lastVerifiedAt = .init()
            profileStore.save(updated)
            popoverVM.profile = updated
            settingsVM.profile = updated
            popoverVM.lastError = nil
        } catch {
            logger.error("Recheck failed: \(error)")
            popoverVM.lastError = (error as? HermesError)?.errorDescription
        }
    }

    func refreshHealth() async {
        guard let profile = profileStore.profile,
              let bearer = currentBearer() else { return }
        let client = HermesClient(baseURL: profile.baseURL, bearerToken: bearer)
        settingsVM.detailedHealth = try? await client.detailedHealth()
    }
}

/// Tiny adapter so AppEnvironment can react to NSWindow close without subclassing.
private final class AnyWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
