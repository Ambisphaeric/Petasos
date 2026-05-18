import AppKit
import Carbon.HIToolbox
import Foundation
import PetasosSpeech

/// Wraps Carbon's `RegisterEventHotKey` so we can react to a system-wide key
/// combo with both press and release events — what push-to-talk needs.
///
/// `kEventHotKeyPressed` and `kEventHotKeyReleased` are both reliable on
/// macOS 11+. We deliberately do NOT use NSEvent global monitors because they
/// drop key-up events for combos involving modifier keys and require
/// Accessibility permission.
@MainActor
final class GlobalHotkey {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var currentCombo: SpeechPreferences.HotkeyCombo?

    /// Replace any prior registration with `combo`. Pass `nil` to unregister.
    func register(combo: SpeechPreferences.HotkeyCombo?) {
        unregister()
        guard let combo else { return }
        currentCombo = combo

        // Install the handler once (idempotent — we unregister above).
        var spec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                let instance = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(eventRef)
                if kind == UInt32(kEventHotKeyPressed) {
                    DispatchQueue.main.async { instance.onKeyDown?() }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    DispatchQueue.main.async { instance.onKeyUp?() }
                }
                return noErr
            },
            spec.count,
            &spec,
            selfPtr,
            &handlerRef
        )

        let hotkeyID = EventHotKeyID(signature: OSType(0x50_54_53_53 /* "PTSS" */), id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        if status != noErr {
            NSLog("[petasos.hotkey] RegisterEventHotKey failed: \(status) for combo \(combo.displayString)")
            hotkeyRef = nil
        } else {
            NSLog("[petasos.hotkey] registered \(combo.displayString)")
        }
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let h = handlerRef {
            RemoveEventHandler(h)
            handlerRef = nil
        }
        currentCombo = nil
    }
}

/// Helpers for converting a captured `NSEvent.keyDown` into the Carbon-style
/// representation we persist.
enum HotkeyEncoding {
    /// Carbon modifier flag bits (cmdKey/shiftKey/optionKey/controlKey live in
    /// the 8–13 range, distinct from NSEvent.modifierFlags which are in the
    /// 16–24 range).
    static let cmdKey: UInt32 = 1 << 8
    static let shiftKey: UInt32 = 1 << 9
    static let optionKey: UInt32 = 1 << 11
    static let controlKey: UInt32 = 1 << 12

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= cmdKey }
        if flags.contains(.shift)    { m |= shiftKey }
        if flags.contains(.option)   { m |= optionKey }
        if flags.contains(.control)  { m |= controlKey }
        return m
    }

    static func displayString(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.shift)    { parts.append("⇧") }
        if flags.contains(.command)  { parts.append("⌘") }
        parts.append(keyLabel(for: keyCode))
        return parts.joined()
    }

    /// Best-effort symbolic label for a virtual key code. Covers the keys
    /// users are most likely to bind. Falls back to `key:NN` for unknown codes.
    static func keyLabel(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩︎"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "key:\(keyCode)"
        }
    }
}
