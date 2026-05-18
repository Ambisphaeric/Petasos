import Foundation

public struct HotkeyBinding: Codable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String           // semantic id: "ptt", "toggle_overlay", "screenshot", etc.
    public let displayName: String
    public var keyCode: UInt32?     // Carbon virtual key code; nil means unbound
    public var modifierFlags: UInt32

    public init(id: String, displayName: String, keyCode: UInt32?, modifierFlags: UInt32) {
        self.id = id
        self.displayName = displayName
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    public var isBound: Bool { keyCode != nil }
}

public enum HotkeyID {
    public static let pushToTalk = "ptt"
    public static let toggleDictation = "toggle_dictation"
    public static let toggleOverlay = "toggle_overlay"
    public static let screenshot = "screenshot"
    public static let readAloud = "read_aloud"
    public static let stop = "stop"
    public static let expandShorthand = "expand_shorthand"
    public static let speakStatus = "speak_status"
}
