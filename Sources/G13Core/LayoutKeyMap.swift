import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Maps a desired character to the (keyCode, needsShift) that produces it under
/// the CURRENT keyboard layout. Without this, hard-coded ANSI keycodes type the
/// wrong characters on non-ANSI layouts (e.g. JIS: ANSI "=" keycode is "^").
public enum LayoutKeyMap {
    public typealias Key = (code: CGKeyCode, shift: Bool)

    private static var cachedSourceID: String?
    private static var map: [Character: Key] = [:]
    /// `map` without dead keys: a tapped dead key (´ ^ ¨ on German/French, ' " on
    /// US-International…) starts an accent instead of typing its character.
    private static var typableMap: [Character: Key] = [:]

    public static func resolve(_ character: Character) -> Key? {
        refresh()
        return map[character]
    }

    /// Like `resolve`, but only keys that type the character in a single tap.
    public static func resolveTypable(_ character: Character) -> Key? {
        refresh()
        return typableMap[character]
    }

    /// `resolveTypable`'s table for an installed layout other than the current
    /// one (e.g. "com.apple.keylayout.USInternational-PC"); nil if not installed.
    public static func typableKeys(layoutID: String) -> [Character: Key]? {
        let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return nil }
        return build(source)?.typable
    }

    private static func refresh() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        let id = inputSourceID(source)
        if id == cachedSourceID, !map.isEmpty { return }
        if let maps = build(source) {
            map = maps.all
            typableMap = maps.typable
            cachedSourceID = id
        }
    }

    private static func build(_ source: TISInputSource) -> (all: [Character: Key], typable: [Character: Key])? {
        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var all: [Character: Key] = [:]
        var typable: [Character: Key] = [:]

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
                        let key: Key = (CGKeyCode(code), shift)
                        if all[c] == nil { all[c] = key }
                        if typable[c] == nil,
                           !isDeadKey(layout, code: code, modifierState: modifierState, kbdType: kbdType) {
                            typable[c] = key
                        }
                    }
                }
            }
        }
        if all.isEmpty { return nil }
        return (all: all, typable: typable)
    }

    /// A dead key produces no character on its own key-down; it only leaves a
    /// pending dead-key state for the next key to combine with.
    private static func isDeadKey(_ layout: UnsafePointer<UCKeyboardLayout>, code: Int,
                                  modifierState: UInt32, kbdType: UInt32) -> Bool {
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let err = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown),
                                 modifierState, kbdType, 0,
                                 &deadKeyState, 4, &length, &chars)
        return err == noErr && length == 0 && deadKeyState != 0
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}
