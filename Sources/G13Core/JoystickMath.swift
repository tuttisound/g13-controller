import Foundation

/// Pure joystick interpretation (kept separate from the driver so it's testable).
public enum JoystickMath {
    /// Centered deltas with inversion applied.
    public static func centeredDelta(x: Int, y: Int, settings: JoystickSettings) -> (dx: Int, dy: Int) {
        let c = Int(settings.center)
        var dx = x - c
        var dy = y - c
        if settings.invertX { dx = -dx }
        if settings.invertY { dy = -dy }
        return (dx, dy)
    }

    public static func withinDeadzone(x: Int, y: Int, settings: JoystickSettings) -> Bool {
        let (dx, dy) = centeredDelta(x: x, y: y, settings: settings)
        let dz = Int(settings.deadzone)
        return abs(dx) <= dz && abs(dy) <= dz
    }

    /// Direction set with hysteresis: enter at `deadzone`, exit at `deadzone-8`,
    /// preventing chatter at the boundary.
    public static func directions(x: Int, y: Int, settings: JoystickSettings,
                                  previous: Set<InputID>) -> Set<InputID> {
        let (dx, dy) = centeredDelta(x: x, y: y, settings: settings)
        let enter = Int(settings.deadzone)
        let exit = max(4, enter - 8)
        var dirs = previous

        func axis(_ d: Int, neg: InputID, pos: InputID) {
            if d < -enter { dirs.insert(neg); dirs.remove(pos) }
            else if d > enter { dirs.insert(pos); dirs.remove(neg) }
            else {
                if dirs.contains(neg), d > -exit { dirs.remove(neg) }
                if dirs.contains(pos), d < exit { dirs.remove(pos) }
            }
        }
        axis(dx, neg: .joyLeft, pos: .joyRight)
        axis(dy, neg: .joyUp, pos: .joyDown)
        return dirs
    }

    /// Movement/scroll delta beyond the deadzone, scaled 0…`speed` by deflection.
    public static func scaled(x: Int, y: Int, settings: JoystickSettings, speed: Double) -> (dx: Int, dy: Int) {
        var (dx, dy) = centeredDelta(x: x, y: y, settings: settings)
        let dz = Int(settings.deadzone)
        dx = beyondDeadzone(dx, dz)
        dy = beyondDeadzone(dy, dz)
        let range = Double(max(1, 127 - dz))
        return (Int((Double(dx) / range) * speed), Int((Double(dy) / range) * speed))
    }

    private static func beyondDeadzone(_ d: Int, _ dz: Int) -> Int {
        if abs(d) <= dz { return 0 }
        return d > 0 ? d - dz : d + dz
    }
}
