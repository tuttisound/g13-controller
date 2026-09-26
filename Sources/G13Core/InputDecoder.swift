import Foundation

/// Decodes the G13's 8-byte interrupt-IN report into an `InputFrame`.
///
/// Byte layout (report begins with the 0x01 marker byte):
/// ```
///   [0] 0x01 marker
///   [1] joystick X (0-255, ~128 center)
///   [2] joystick Y (0-255, ~128 center)
///   [3] G1..G8        (bit0=G1 ... bit7=G8)
///   [4] G9..G16
///   [5] G17..G22      (bits0-5), bit6 = light (ignored)
///   [6] bit0=BD, bits1-4=L1..L4, bits5-7=M1/M2/M3
///   [7] bit0=MR, bit1=LEFT, bit2=RIGHT, bit3=STICK, bits4-7 light flags (ignored)
/// ```
public enum InputDecoder {
    public static let reportLength = 8

    /// Decode a normalized report buffer. Returns nil if the buffer is too short
    /// or does not begin with the 0x01 marker.
    public static func decode(_ data: Data) -> InputFrame? {
        var b = [UInt8](data)
        // Accept a 7-byte data-only frame (id stripped) by restoring the marker.
        if b.count == 7 { b = [0x01] + b }
        guard b.count >= reportLength, b[0] == 0x01 else { return nil }

        var frame = InputFrame()
        frame.joyX = b[1]
        frame.joyY = b[2]

        var buttons = Set<InputID>()
        addBits(b[3], &buttons, [.g1, .g2, .g3, .g4, .g5, .g6, .g7, .g8])
        addBits(b[4], &buttons, [.g9, .g10, .g11, .g12, .g13, .g14, .g15, .g16])
        addBits(b[5], &buttons, [.g17, .g18, .g19, .g20, .g21, .g22, nil, nil])
        addBits(b[6], &buttons, [.bd, .l1, .l2, .l3, .l4, nil, nil, nil])
        addBits(b[7], &buttons, [nil, .left, .right, .stickClick, nil, nil, nil, nil])
        frame.buttons = buttons

        var mKeys = Set<MKey>()
        if b[6] & (1 << 5) != 0 { mKeys.insert(.m1) }
        if b[6] & (1 << 6) != 0 { mKeys.insert(.m2) }
        if b[6] & (1 << 7) != 0 { mKeys.insert(.m3) }
        if b[7] & (1 << 0) != 0 { mKeys.insert(.mr) }
        frame.mKeys = mKeys

        return frame
    }

    private static func addBits(_ byte: UInt8, _ set: inout Set<InputID>, _ mapping: [InputID?]) {
        for bit in 0..<8 where byte & (1 << bit) != 0 {
            if let id = mapping[bit] { set.insert(id) }
        }
    }
}

/// Converts consecutive `InputFrame`s into press/release edge events.
///
/// The G13 reports full state every frame, so set-difference is the natural,
/// correct debounce for buttons — no timers needed. Joystick analog changes are
/// forwarded raw; their interpretation (directions / mouse / scroll) happens on
/// the main actor where the active settings live.
public final class InputStateTracker {
    private var previous = InputFrame()
    private var hasPrevious = false

    public init() {}

    public func reset() {
        previous = InputFrame()
        hasPrevious = false
    }

    public func process(_ frame: InputFrame) -> [InputEvent] {
        var events: [InputEvent] = []

        guard hasPrevious else {
            previous = frame
            hasPrevious = true
            events.append(.joystick(x: frame.joyX, y: frame.joyY))
            for id in frame.buttons.sorted(by: stableOrder) { events.append(.down(id)) }
            for m in frame.mKeys.sorted(by: { $0.bankIndex < $1.bankIndex }) { events.append(.bankKey(m)) }
            return events
        }

        let pressed = frame.buttons.subtracting(previous.buttons)
        let released = previous.buttons.subtracting(frame.buttons)
        for id in pressed.sorted(by: stableOrder) { events.append(.down(id)) }
        for id in released.sorted(by: stableOrder) { events.append(.up(id)) }

        let mPressed = frame.mKeys.subtracting(previous.mKeys)
        for m in mPressed.sorted(by: { $0.bankIndex < $1.bankIndex }) { events.append(.bankKey(m)) }

        if frame.joyX != previous.joyX || frame.joyY != previous.joyY {
            events.append(.joystick(x: frame.joyX, y: frame.joyY))
        }

        previous = frame
        return events
    }

    private func stableOrder(_ a: InputID, _ b: InputID) -> Bool {
        a.rawValue < b.rawValue
    }
}
