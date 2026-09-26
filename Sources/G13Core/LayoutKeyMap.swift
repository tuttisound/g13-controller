import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Maps a desired character to the (keyCode, needsShift) that produces it under
/// the CURRENT keyboard layout. Without this, hard-coded ANSI keycodes type the
/// wrong characters on non-ANSI layouts (e.g. JIS: ANSI "=" keycode is "^").
public enum LayoutKeyMap {
    private static var cachedSourceID: String?
    private static var map: [Character: (code: CGKeyCode, shift: Bool)] = [:]

    public static func resolve(_ character: Character) -> (code: CGKeyCode, shift: Bool)? {
        refresh()
        return map[character]
    }

    private static func refresh() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        let id = inputSourceID(source)
        if id == cachedSourceID, !map.isEmpty { return }

        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var newMap: [Character: (code: CGKeyCode, shift: Bool)] = [:]

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            let kbdType = UInt32(LMGetKbdType())
            // Keypad keycodes — exclude so e.g. "=" resolves to the main-row key,
            // not Keypad-Equals (Cmd+KeypadEquals doesn't trigger app shortcuts).
            let keypad: Set<Int> = [0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E, 0x51,
                                    0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]
            for shift in [false, true] {
                let modifierState: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
                for code in 0..<128 {
                    if keypad.contains(code) { continue }
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let err = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay),
                                             modifierState, kbdType,
                                             OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                             &deadKeyState, 4, &length, &chars)
                    if err == noErr, length == 1, let scalar = Unicode.Scalar(chars[0]) {
                        let c = Character(scalar)
                        if newMap[c] == nil { newMap[c] = (CGKeyCode(code), shift) }
                    }
                }
            }
        }
        if !newMap.isEmpty {
            map = newMap
            cachedSourceID = id
        }
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
