import AppKit
import SwiftUI
import PetasosSpeech

/// SwiftUI control for capturing a global hotkey combo.
///
/// Idle state shows the current combo's display string. Clicking enters
/// "capture" mode: the next `keyDown` with at least one modifier is recorded;
/// Escape cancels. While in capture mode we install an `NSEvent` local monitor
/// so the keypress doesn't propagate to whatever else has focus.
public struct HotkeyRecorder: View {
    @Binding var combo: SpeechPreferences.HotkeyCombo
    @State private var capturing: Bool = false
    @State private var monitor: Any?

    public init(combo: Binding<SpeechPreferences.HotkeyCombo>) {
        self._combo = combo
    }

    public var body: some View {
        Button {
            if capturing { stopCapture() } else { startCapture() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: capturing ? "record.circle" : "keyboard")
                    .foregroundStyle(capturing ? .red : .secondary)
                Text(capturing ? "Press combo… (Esc to cancel)" : combo.displayString)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(minWidth: 180, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(capturing ? "Recording hotkey. Press a key combination, or Escape to cancel." : "Hotkey: \(combo.displayString). Click to change.")
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        guard monitor == nil else { return }
        capturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape always cancels.
            if event.keyCode == 0x35 {
                stopCapture()
                return nil
            }
            // Require at least one modifier so the combo doesn't collide with
            // bare typing in other apps.
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let usable: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            if mods.intersection(usable).isEmpty {
                NSSound.beep()
                return nil
            }
            let carbon = HotkeyEncoding.carbonModifiers(from: mods)
            let label = HotkeyEncoding.displayString(keyCode: event.keyCode, flags: mods)
            combo = SpeechPreferences.HotkeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbon,
                displayString: label
            )
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        capturing = false
    }
}

// Hotkey recorder needs HotkeyEncoding from the executable target. Mirror the
// minimal subset here so PetasosUI doesn't have to depend on AppKit-only Carbon
// symbols indirectly through the app target.
private enum HotkeyEncoding {
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

    static func keyLabel(for keyCode: UInt16) -> String {
        // Keep in sync with the AppDelegate-side HotkeyEncoding.keyLabel.
        switch Int(keyCode) {
        case 49: return "Space"
        case 36: return "↩︎"
        case 48: return "⇥"
        case 53: return "⎋"
        case 51: return "⌫"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64:  return "F17"
        case 79:  return "F18"
        case 80:  return "F19"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        default: return "key:\(keyCode)"
        }
    }
}
