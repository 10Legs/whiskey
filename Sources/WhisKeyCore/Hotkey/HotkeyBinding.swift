import CoreGraphics
import Foundation

/// A single user-configured mapping from a key combo to a `HotkeyAction`.
///
/// `keyCode` and `modifierFlags` are both optional. When both are nil the
/// binding is considered "not set" and the action has no active hotkey.
///
/// Right Option is represented as keyCode 0x3D with nil modifierFlags —
/// the event tap fires a `flagsChanged` event rather than a `keyDown`, so
/// modifier-key-only bindings carry no additional modifier mask.
///
/// `CGKeyCode` and `CGEventFlags` are not synthesised-`Codable`, so manual
/// conformance encodes them as their underlying integer types (`UInt16` / `UInt64`).
public struct HotkeyBinding: Sendable {
    public let action: HotkeyAction
    public var keyCode: CGKeyCode?
    public var modifierFlags: CGEventFlags?

    public init(action: HotkeyAction, keyCode: CGKeyCode? = nil, modifierFlags: CGEventFlags? = nil) {
        self.action = action
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

// MARK: - Codable (manual — CGKeyCode/CGEventFlags need raw-value bridging)

extension HotkeyBinding: Codable {
    private enum CodingKeys: String, CodingKey {
        case action, keyCode, modifierFlagsRaw
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(HotkeyAction.self, forKey: .action)
        if let raw = try container.decodeIfPresent(UInt16.self, forKey: .keyCode) {
            keyCode = CGKeyCode(raw)
        } else {
            keyCode = nil
        }
        if let raw = try container.decodeIfPresent(UInt64.self, forKey: .modifierFlagsRaw) {
            modifierFlags = CGEventFlags(rawValue: raw)
        } else {
            modifierFlags = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(keyCode.map { UInt16($0) }, forKey: .keyCode)
        try container.encodeIfPresent(modifierFlags.map { $0.rawValue }, forKey: .modifierFlagsRaw)
    }
}

// MARK: - Display

extension HotkeyBinding {
    /// Human-readable representation of the key combo.
    ///
    /// Examples:
    /// - Right Option only:  "⌥ (Right Opt)"
    /// - ⌃⌥P:               "⌃⌥P"
    /// - Not set:            "Not set"
    public var displayString: String {
        guard let keyCode else { return "Not set" }
        let modPart = modifierSymbols(for: modifierFlags)
        let keyPart = keyName(for: keyCode)
        // Right Option special-case (keyCode 0x3D, no modifiers).
        if keyCode == 0x3D && (modifierFlags == nil || modifierFlags == []) {
            return "⌥ (Right Opt)"
        }
        return modPart + keyPart
    }

    // MARK: - Private helpers

    /// Returns modifier symbols in macOS HIG order: ⌃ ⌥ ⇧ ⌘.
    private func modifierSymbols(for flags: CGEventFlags?) -> String {
        guard let flags else { return "" }
        var result = ""
        if flags.contains(.maskControl) { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift) { result += "⇧" }
        if flags.contains(.maskCommand) { result += "⌘" }
        return result
    }

    // swiftlint:disable cyclomatic_complexity
    /// Returns a display name for the given virtual key code.
    private func keyName(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 0x24: return "⏎"   // Return
        case 0x33: return "⌫"   // Delete / Backspace
        case 0x75: return "⌦"   // Forward Delete
        case 0x35: return "⎋"   // Escape
        case 0x30: return "⇥"   // Tab
        case 0x31: return "Space"
        case 0x7E: return "↑"   // Arrow Up
        case 0x7D: return "↓"   // Arrow Down
        case 0x7B: return "←"   // Arrow Left
        case 0x7C: return "→"   // Arrow Right
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        case 0x6A: return "F16"
        case 0x40: return "F17"
        case 0x4F: return "F18"
        case 0x50: return "F19"
        case 0x3D: return "⌥"   // Right Option (bare)
        case 0x3A: return "⌥"   // Left Option (bare)
        default:
            // Map common printable key codes to their characters.
            return printableCharacter(for: keyCode)
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// Attempts to derive a printable character from a key code using a minimal
    /// hard-coded table for letter and digit keys. Falls back to "Key \(keyCode)".
    private func printableCharacter(for keyCode: CGKeyCode) -> String {
        // ANSI key codes for letter keys (A–Z, uppercase per HIG display rules).
        let letterMap: [CGKeyCode: String] = [
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
            0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
            0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z"
        ]
        // Digit key codes 0–9.
        let digitMap: [CGKeyCode: String] = [
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9"
        ]
        // Common punctuation.
        let punctuationMap: [CGKeyCode: String] = [
            0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x2A: "\\",
            0x29: ";", 0x27: "'", 0x2B: ",", 0x2F: ".", 0x2C: "/", 0x32: "`"
        ]
        return letterMap[keyCode] ?? digitMap[keyCode] ?? punctuationMap[keyCode]
            ?? "Key \(keyCode)"
    }
}
