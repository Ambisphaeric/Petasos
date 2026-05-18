import AppKit
import Combine
import Foundation

/// Observes system-wide accessibility preferences and republishes them as ObservableObject state.
/// Driven by NSWorkspace.accessibilityDisplayOptionsDidChange and VoiceOver status notifications.
@MainActor
public final class SystemAccessibilityFlags: ObservableObject {
    @Published public private(set) var reduceMotion: Bool
    @Published public private(set) var reduceTransparency: Bool
    @Published public private(set) var increaseContrast: Bool
    @Published public private(set) var differentiateWithoutColor: Bool
    @Published public private(set) var voiceOverRunning: Bool

    private var cancellables: Set<AnyCancellable> = []

    public init() {
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        self.differentiateWithoutColor = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        self.voiceOverRunning = Self.detectVoiceOver()

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.apple.universalaccess.voiceOverEnabledDidChange"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        differentiateWithoutColor = NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
        voiceOverRunning = Self.detectVoiceOver()
    }

    private static func detectVoiceOver() -> Bool {
        // VoiceOver writes its on/off state into the universalaccess domain.
        // CFPreferences reads it without requiring sandbox exemptions for this domain.
        let key = "voiceOverOnOffKey" as CFString
        let domain = "com.apple.universalaccess" as CFString
        var keyExists: DarwinBoolean = false
        let value = CFPreferencesGetAppBooleanValue(key, domain, &keyExists)
        return keyExists.boolValue && value
    }
}
