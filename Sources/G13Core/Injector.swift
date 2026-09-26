import Foundation
import CoreGraphics
import AppKit

/// Low-level CoreGraphics injection primitives shared by `ActionEngine`,
/// `MacroPlayer`, and the joystick driver. All events go through `EventTagger`
/// so they carry our marker and use the shared private source.
enum Injector {
    static func location() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, tagger: EventTagger) {
        guard let e = CGEvent(keyboardEventSource: tagger.source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        tagger.post(e)
    }

    /// Inject a string as Unicode (layout-independent) via a synthetic key event.
    static func text(_ s: String, tagger: EventTagger) {
        let utf16 = Array(s.utf16)
        guard !utf16.isEmpty,
              let down = CGEvent(keyboardEventSource: tagger.source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: tagger.source, virtualKey: 0, keyDown: false)
        else { return }
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        tagger.post(down)
        tagger.post(up)
    }

    static func mouseButton(_ b: MouseButton, down: Bool, clickState: Int64 = 1, tagger: EventTagger) {
        let e: CGEvent?
        if let number = b.otherButtonNumber {
            // center(2) / back(3) / forward(4): otherMouse with an explicit button number.
            e = CGEvent(mouseEventSource: tagger.source,
                        mouseType: down ? .otherMouseDown : .otherMouseUp,
                        mouseCursorPosition: location(), mouseButton: .center)
            e?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(number))
        } else {
            let type: CGEventType = b == .left
                ? (down ? .leftMouseDown : .leftMouseUp)
                : (down ? .rightMouseDown : .rightMouseUp)
            e = CGEvent(mouseEventSource: tagger.source, mouseType: type,
                        mouseCursorPosition: location(), mouseButton: b == .left ? .left : .right)
        }
        guard let event = e else { return }
        if clickState != 1 { event.setIntegerValueField(.mouseEventClickState, value: clickState) }
        tagger.post(event)
    }

    /// Synthesize a media / system key (play, volume, etc.) via the systemDefined
    /// NSEvent technique (down then up).
    static func mediaKey(_ key: MediaKey, tagger: EventTagger) {
        for down in [true, false] {
            let flags = down ? 0xA00 : 0xB00
            let data1 = (key.nxKeyType << 16) | flags
            guard let ev = NSEvent.otherEvent(with: .systemDefined,
                                              location: .zero,
                                              modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                                              timestamp: 0, windowNumber: 0, context: nil,
                                              subtype: 8, data1: data1, data2: -1),
                  let cg = ev.cgEvent else { continue }
            tagger.tag(cg)
            cg.post(tap: .cghidEventTap)
        }
    }

    static func click(_ b: MouseButton, count: Int, tagger: EventTagger) {
        for i in 1...max(1, count) {
            mouseButton(b, down: true, clickState: Int64(i), tagger: tagger)
            mouseButton(b, down: false, clickState: Int64(i), tagger: tagger)
        }
    }

    static func move(dx: Int, dy: Int, tagger: EventTagger) {
        let loc = location()
        let p = CGPoint(x: loc.x + CGFloat(dx), y: loc.y + CGFloat(dy))
        if let e = CGEvent(mouseEventSource: tagger.source, mouseType: .mouseMoved,
                           mouseCursorPosition: p, mouseButton: .left) {
            tagger.post(e)
        }
    }

    /// wheel1 = vertical, wheel2 = horizontal.
    static func scroll(dx: Int, dy: Int, tagger: EventTagger) {
        if let e = CGEvent(scrollWheelEvent2Source: tagger.source, units: .pixel,
                           wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
            tagger.post(e)
        }
    }
}

extension ModifierSet {
    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.command) { f.insert(.maskCommand) }
        if contains(.shift) { f.insert(.maskShift) }
        if contains(.option) { f.insert(.maskAlternate) }
        if contains(.control) { f.insert(.maskControl) }
        if contains(.function) { f.insert(.maskSecondaryFn) }
        return f
    }
}
