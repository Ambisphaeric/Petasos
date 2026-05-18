import Foundation

/// Pluggable transparent overlay modes. P0: protocol only.
/// P3 ships CaptionBarMode, ComposeBoxMode, SideRailMode.
/// P4 adds FocusRingMode, ThoughtBubbleMode.
public protocol OverlayMode: AnyObject, Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    static var defaultAccessibilityProfile: AccessibilityProfile { get }

    /// Whether this mode is safe to use under WCAG-equivalent strict mode.
    /// CaptionBar/ComposeBox = true; SideRail/FocusRing/ThoughtBubble = depends on opacity/font settings.
    static var isWCAGFriendly: Bool { get }

    func start(profile: AccessibilityProfile) async
    func stop() async
    func updateProfile(_ profile: AccessibilityProfile) async
}
