import Foundation

/// Interprets the analog joystick per `JoystickSettings`:
/// - `.directionalKeys` → emits joyUp/Down/Left/Right edges (routed to bindings)
/// - `.mouseMove`       → relative cursor movement at ~60Hz
/// - `.scrollWheel`     → vertical + horizontal scroll at ~60Hz
/// - `.disabled`        → nothing
@MainActor
public final class JoystickDriver {
    public enum DirectionEdge: Equatable, Sendable { case down(InputID); case up(InputID) }

    /// Direction edges (only in `.directionalKeys` mode), routed through bindings.
    public var onDirection: ((DirectionEdge) -> Void)?
    public var settings = JoystickSettings()

    private let engine: ActionEngine
    private var lastDirections: Set<InputID> = []
    private var latestX = 128
    private var latestY = 128
    private var driveTask: Task<Void, Never>?

    public init(engine: ActionEngine) { self.engine = engine }

    public func update(x: UInt8, y: UInt8) {
        latestX = Int(x)
        latestY = Int(y)
        switch settings.mode {
        case .directionalKeys:
            stopDriving()
            updateDirections()
        case .mouseMove, .scrollWheel:
            clearDirections()
            if JoystickMath.withinDeadzone(x: latestX, y: latestY, settings: settings) {
                stopDriving()
            } else {
                ensureDriving()
            }
        case .disabled:
            stopDriving()
            clearDirections()
        }
    }

    /// Release everything (device removed, master disabled, mode changed).
    public func reset() {
        stopDriving()
        clearDirections()
        latestX = Int(settings.center)
        latestY = Int(settings.center)
    }

    // MARK: - Directional

    private func updateDirections() {
        let dirs = JoystickMath.directions(x: latestX, y: latestY, settings: settings, previous: lastDirections)
        for d in lastDirections.subtracting(dirs) { onDirection?(.up(d)) }
        for d in dirs.subtracting(lastDirections) { onDirection?(.down(d)) }
        lastDirections = dirs
    }

    private func clearDirections() {
        for d in lastDirections { onDirection?(.up(d)) }
        lastDirections = []
    }

    // MARK: - Continuous (mouse / scroll)

    private func ensureDriving() {
        guard driveTask == nil else { return }
        driveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
            }
        }
    }

    private func stopDriving() {
        driveTask?.cancel()
        driveTask = nil
    }

    private func tick() {
        switch settings.mode {
        case .mouseMove:
            let (dx, dy) = JoystickMath.scaled(x: latestX, y: latestY, settings: settings, speed: settings.mouseSpeed * 2)
            if dx != 0 || dy != 0 { engine.moveMouse(dx: dx, dy: dy) }
        case .scrollWheel:
            let (dx, dy) = JoystickMath.scaled(x: latestX, y: latestY, settings: settings, speed: settings.scrollSpeed * 2)
            // wheel1 = vertical; stick up (dy<0) should scroll up → pass -dy
            if dx != 0 || dy != 0 { engine.scroll(dx: dx, dy: -dy) }
        default:
            stopDriving()
        }
    }
}
