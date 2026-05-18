import AppKit
import CoreGraphics
import Foundation
import Network

/// Single entry point for the macOS TCC permissions Petasos uses. Microphone
/// stays in PetasosSpeech.AudioPermissions because the speech subsystem already
/// owns that flow; this enum covers the platform-level prompts users hit during
/// onboarding and feature use.
@MainActor
public enum Permissions {

    public enum Status: Sendable, Equatable {
        case notDetermined
        case authorized
        case denied
    }

    // MARK: - Local Network

    /// Local network permission has no public preflight API. We expose a way
    /// to trigger the system prompt early so it doesn't surprise the user mid
    /// flow. Pair with NSLocalNetworkUsageDescription in Info.plist for nice
    /// copy on the dialog.
    public static func primeLocalNetworkAccess() {
        // Starting any NWBrowser is enough to bring up the system prompt the
        // first time. We pick a benign Bonjour type and stop the browser as
        // soon as it's running. We don't care about its results.
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                browser.cancel()
            default:
                break
            }
        }
        browser.start(queue: .main)
        // Cancel after a short window so we never leave an idle browser
        // running, regardless of whether the user clicked allow or deny.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { browser.cancel() }
    }

    // MARK: - Screen Recording

    /// macOS doesn't reveal `authorized` vs `notDetermined` for screen
    /// recording via the public API — `CGPreflightScreenCaptureAccess()`
    /// returns true only when access is granted, otherwise false (covering
    /// both denied and never-asked). That's enough for surfacing a "grant"
    /// button when status is anything other than authorized.
    public static func screenRecordingStatus() -> Status {
        CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined
    }

    /// Triggers the system prompt the first time it's called per install.
    /// On subsequent calls when permission was denied, macOS does *not*
    /// re-prompt — it silently returns false. In that case open System
    /// Settings → Privacy & Security → Screen Recording for the user.
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            openPrivacyPane(.screenRecording)
        }
        return granted
    }

    // MARK: - System Audio

    /// System audio capture in Petasos goes through ScreenCaptureKit
    /// (SCStream with `capturesAudio = true`), which uses the same TCC
    /// permission as screen recording. macOS 14.4+ also exposes a separate
    /// CoreAudio process-tap API gated by NSAudioCaptureUsageDescription;
    /// we declare that key in Info.plist so the door is open, but route
    /// today's requests through the SCK permission for one-prompt UX.
    public static func systemAudioStatus() -> Status { screenRecordingStatus() }

    @discardableResult
    public static func requestSystemAudio() -> Bool { requestScreenRecording() }

    // MARK: - System Settings deep links

    public enum PrivacyPane: String {
        case screenRecording = "Privacy_ScreenCapture"
        case microphone = "Privacy_Microphone"
        case localNetwork = "Privacy_LocalNetwork"
    }

    public static func openPrivacyPane(_ pane: PrivacyPane) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspace.shared.open(url)
    }
}
