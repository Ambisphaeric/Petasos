import AppKit
import Foundation

/// Posts accessibility announcements via NSAccessibility — VoiceOver speaks them
/// even when the focused element hasn't changed. Used to surface streaming-only
/// events (tool progress, errors) to blind users without forcing focus moves.
///
/// On macOS, `accessibilityLiveRegion(_:)` is only available on 15+. Posting
/// announcement notifications directly is the supported pre-15 path and is
/// also the standard pattern in production macOS apps.
@MainActor
public enum StatusAnnouncer {
    public enum Priority {
        case low, high
    }

    public static func announce(_ text: String, priority: Priority) {
        let nsPriority: NSAccessibilityPriorityLevel = (priority == .high) ? .high : .low
        let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: text,
            .priority: nsPriority.rawValue
        ]
        let target: Any = NSApp.mainWindow ?? NSApp as Any
        NSAccessibility.post(
            element: target,
            notification: .announcementRequested,
            userInfo: userInfo
        )
    }
}
