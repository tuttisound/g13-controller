import Foundation
import CoreGraphics

/// A stable, human-readable key identifier (e.g. "a", "return", "f5", "kpEnter").
/// Stored as a string so config JSON is editable and resilient to table changes.
public struct KeyName: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

/// Maps `KeyName` ↔ macOS virtual key codes (ANSI layout constants). Also the
/// canonical source for the GUI's key picker (`groups`).
public enum KeyCodeTable {
    /// canonical name → virtual keycode
    public static let nameToCode: [String: CGKeyCode] = [
        // Letters
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E, "f": 0x03,
        "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26, "k": 0x28, "l": 0x25,
        "m": 0x2E, "n": 0x2D, "o": 0x1F, "p": 0x23, "q": 0x0C, "r": 0x0F,
        "s": 0x01, "t": 0x11, "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07,
        "y": 0x10, "z": 0x06,
        // Digits (top row)
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
        // Punctuation
        "minus": 0x1B, "equal": 0x18, "leftBracket": 0x21, "rightBracket": 0x1E,
        "backslash": 0x2A, "semicolon": 0x29, "quote": 0x27, "grave": 0x32,
        "comma": 0x2B, "period": 0x2F, "slash": 0x2C,
        // Whitespace / control
        "return": 0x24, "tab": 0x30, "space": 0x31, "delete": 0x33,
        "escape": 0x35, "forwardDelete": 0x75, "help": 0x72,
        // Navigation
        "home": 0x73, "end": 0x77, "pageUp": 0x74, "pageDown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
        // Function keys
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61,
        "f7": 0x62, "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
        "f13": 0x69, "f14": 0x6B, "f15": 0x71, "f16": 0x6A, "f17": 0x40,
        "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        // Keypad
        "kp0": 0x52, "kp1": 0x53, "kp2": 0x54, "kp3": 0x55, "kp4": 0x56,
        "kp5": 0x57, "kp6": 0x58, "kp7": 0x59, "kp8": 0x5B, "kp9": 0x5C,
        "kpDecimal": 0x41, "kpPlus": 0x45, "kpMinus": 0x4E, "kpMultiply": 0x43,
        "kpDivide": 0x4B, "kpEnter": 0x4C, "kpEquals": 0x51, "kpClear": 0x47,
        // Media
        "volumeUp": 0x48, "volumeDown": 0x49, "mute": 0x4A,
        // Modifier keys (as standalone, for macros pressing a bare modifier)
        "command": 0x37, "rightCommand": 0x36, "shift": 0x38, "rightShift": 0x3C,
        "option": 0x3A, "rightOption": 0x3D, "control": 0x3B, "rightControl": 0x3E,
        "capsLock": 0x39, "function": 0x3F,
    ]

    public static let codeToName: [CGKeyCode: String] = {
        var inv: [CGKeyCode: String] = [:]
        for (name, code) in nameToCode where inv[code] == nil { inv[code] = name }
        return inv
    }()

    public static func keyCode(for name: KeyName) -> CGKeyCode? { nameToCode[name.rawValue] }
    public static func name(for code: CGKeyCode) -> KeyName? { codeToName[code].map { KeyName($0) } }

    /// The printable character a key produces (letters, digits, symbols); nil for
    /// named keys (arrows, function keys, modifiers) whose keycode is layout-stable.
    public static func character(for key: KeyName) -> Character? {
        let r = key.rawValue
        if r.count == 1, let c = r.first, c.isLetter || c.isNumber { return c }
        switch r {
        case "minus": return "-"
        case "equal": return "="
        case "leftBracket": return "["
        case "rightBracket": return "]"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "quote": return "'"
        case "grave": return "`"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        default: return nil
        }
    }

    /// Resolve key+modifiers to the (keyCode, flags) to post, mapping character
    /// keys through the current keyboard layout (so symbols work on JIS etc.).
    public static func resolve(key: KeyName, modifiers: ModifierSet) -> (code: CGKeyCode, flags: CGEventFlags)? {
        if let char = character(for: key), let m = LayoutKeyMap.resolve(char) {
            var flags = modifiers.cgFlags
            if m.shift { flags.insert(.maskShift) }
            return (m.code, flags)
        }
        if let code = keyCode(for: key) {
            return (code, modifiers.cgFlags)
        }
        return nil
    }

    /// Friendly label for the GUI.
    public static func label(for name: KeyName) -> String {
        switch name.rawValue {
        case "return": return "Return"
        case "tab": return "Tab"
        case "space": return "Space"
        case "delete": return "Delete"
        case "forwardDelete": return "Fwd Delete"
        case "escape": return "Esc"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "pageUp": return "Page Up"
        case "pageDown": return "Page Down"
        case "minus": return "-"
        case "equal": return "="
        case "leftBracket": return "["
        case "rightBracket": return "]"
        case "backslash": return "\\"
        case "semicolon": return ";"
        case "quote": return "'"
        case "grave": return "`"
        case "comma": return ","
        case "period": return "."
        case "slash": return "/"
        case "command": return "⌘ Command"
        case "shift": return "⇧ Shift"
        case "option": return "⌥ Option"
        case "control": return "⌃ Control"
        case "capsLock": return "Caps Lock"
        case "function": return "fn"
        default:
            let r = name.rawValue
            if r.hasPrefix("kp") { return "KP " + r.dropFirst(2) }
            if r.count == 1 { return r.uppercased() }
            if r.first == "f", Int(r.dropFirst()) != nil { return r.uppercased() }
            return r.capitalized
        }
    }

    /// Grouped key lists for the GUI picker.
    public static let groups: [(title: String, keys: [KeyName])] = {
        func names(_ ss: [String]) -> [KeyName] { ss.map { KeyName($0) } }
        let letters = "abcdefghijklmnopqrstuvwxyz".map { String($0) }
        let digits = (0...9).map { "\($0)" }
        let fkeys = (1...20).map { "f\($0)" }
        return [
            ("Letters", names(letters)),
            ("Digits", names(digits)),
            ("Function", names(fkeys)),
            ("Navigation", names(["left", "right", "up", "down", "home", "end", "pageUp", "pageDown"])),
            ("Editing", names(["return", "tab", "space", "delete", "forwardDelete", "escape", "help"])),
            ("Punctuation", names(["minus", "equal", "leftBracket", "rightBracket", "backslash",
                                   "semicolon", "quote", "grave", "comma", "period", "slash"])),
            ("Keypad", names(["kp0", "kp1", "kp2", "kp3", "kp4", "kp5", "kp6", "kp7", "kp8", "kp9",
                              "kpDecimal", "kpPlus", "kpMinus", "kpMultiply", "kpDivide", "kpEnter", "kpEquals"])),
            ("Modifiers", names(["command", "shift", "option", "control", "capsLock", "function"])),
            ("Media", names(["volumeUp", "volumeDown", "mute"])),
        ]
    }()
}
