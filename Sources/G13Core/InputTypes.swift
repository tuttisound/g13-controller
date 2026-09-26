import Foundation

/// A logical input on the G13 that can be bound to an action.
///
/// `physicalButtons` are read directly from the input report; the `joy*`
/// directions are synthesized from the analog stick by `InputStateTracker`
/// when the joystick is in directional-keys mode.
public enum InputID: String, Codable, CaseIterable, Hashable, Sendable {
    // 22 programmable G-keys
    case g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11
    case g12, g13, g14, g15, g16, g17, g18, g19, g20, g21, g22
    // "BD" button (left of the LCD)
    case bd
    // Four soft keys beneath the LCD
    case l1, l2, l3, l4
    // Thumb-rest buttons and the joystick click
    case left, right, stickClick
    // Joystick directions (synthesized in .directionalKeys mode)
    case joyUp, joyDown, joyLeft, joyRight

    /// Human-readable label for the GUI.
    public var displayName: String {
        switch self {
        case .bd: return "BD"
        case .left: return "Left"
        case .right: return "Right"
        case .stickClick: return "Stick"
        case .joyUp: return "Joy ↑"
        case .joyDown: return "Joy ↓"
        case .joyLeft: return "Joy ←"
        case .joyRight: return "Joy →"
        default: return rawValue.uppercased()
        }
    }

    /// Physical digital buttons read directly from the report.
    public static let physicalButtons: [InputID] = [
        .g1, .g2, .g3, .g4, .g5, .g6, .g7, .g8, .g9, .g10, .g11,
        .g12, .g13, .g14, .g15, .g16, .g17, .g18, .g19, .g20, .g21, .g22,
        .bd, .l1, .l2, .l3, .l4, .left, .right, .stickClick,
    ]

    /// Joystick-direction virtual inputs.
    public static let joystickDirections: [InputID] = [.joyUp, .joyDown, .joyLeft, .joyRight]

    /// All inputs that are bindable in the GUI (physical + joystick directions).
    public static let bindable: [InputID] = physicalButtons + joystickDirections
}

/// The four backlit mode keys. The G13 hardware has M1/M2/M3 + MR (there is no
/// M4); we use all four to select per-app profile banks (MR == bank 4).
public enum MKey: String, Codable, CaseIterable, Hashable, Sendable {
    case m1, m2, m3, mr

    /// Bank index (0...3) this mode key selects.
    public var bankIndex: Int {
        switch self {
        case .m1: return 0
        case .m2: return 1
        case .m3: return 2
        case .mr: return 3
        }
    }

    public static func forBank(_ index: Int) -> MKey {
        switch index {
        case 0: return .m1
        case 1: return .m2
        case 2: return .m3
        default: return .mr
        }
    }

    public var displayName: String { rawValue.uppercased() }
}

/// One decoded snapshot of the device state (output of `InputDecoder`).
public struct InputFrame: Equatable, Sendable {
    public var buttons: Set<InputID>   // physical digital buttons currently held
    public var mKeys: Set<MKey>        // mode keys currently held
    public var joyX: UInt8
    public var joyY: UInt8

    public init(buttons: Set<InputID> = [], mKeys: Set<MKey> = [],
                joyX: UInt8 = 0x80, joyY: UInt8 = 0x80) {
        self.buttons = buttons
        self.mKeys = mKeys
        self.joyX = joyX
        self.joyY = joyY
    }
}

/// High-level input events produced by `InputStateTracker`.
///
/// `joystick` carries the raw analog value; how it becomes directions, mouse
/// movement, or scrolling is decided downstream (on the main actor) per the
/// active `JoystickSettings`.
public enum InputEvent: Equatable, Sendable {
    case down(InputID)
    case up(InputID)
    case bankKey(MKey)                 // a mode key was pressed (edge) → switch bank
    case joystick(x: UInt8, y: UInt8)  // raw joystick value changed
}
