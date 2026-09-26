import Foundation

// MARK: - Modifiers

public struct ModifierSet: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command  = ModifierSet(rawValue: 1 << 0)
    public static let shift    = ModifierSet(rawValue: 1 << 1)
    public static let option   = ModifierSet(rawValue: 1 << 2)
    public static let control  = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    // Encode as a plain integer for clean JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        rawValue = try c.decode(Int.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Actions

public struct KeyChord: Codable, Hashable, Sendable {
    public var key: KeyName
    public var modifiers: ModifierSet
    /// If true, the key is held while the G13 key is held (engages OS auto-repeat);
    /// otherwise a single down+up tap is sent on press.
    public var repeatsWhileHeld: Bool

    public init(key: KeyName, modifiers: ModifierSet = [], repeatsWhileHeld: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.repeatsWhileHeld = repeatsWhileHeld
    }
}

public enum MouseButton: String, Codable, Hashable, Sendable, CaseIterable {
    case left, right, center, back, forward

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .center: return "Center"
        case .back: return "Back"
        case .forward: return "Forward"
        }
    }

    /// otherMouse button number (center=2, back=3, forward=4); nil for left/right
    /// which use their dedicated event types.
    public var otherButtonNumber: Int? {
        switch self {
        case .center: return 2
        case .back: return 3
        case .forward: return 4
        case .left, .right: return nil
        }
    }
}

public enum MouseDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right

    public var displayName: String { rawValue.capitalized }

    /// Scroll-wheel delta for a per-tick magnitude (dy = vertical wheel1, dx = horizontal wheel2).
    public func scrollDelta(magnitude m: Int) -> (dx: Int, dy: Int) {
        switch self {
        case .up: return (0, m)
        case .down: return (0, -m)
        case .left: return (m, 0)
        case .right: return (-m, 0)
        }
    }

    /// Cursor-move delta for a per-tick magnitude.
    public func moveDelta(magnitude m: Int) -> (dx: Int, dy: Int) {
        switch self {
        case .up: return (0, -m)
        case .down: return (0, m)
        case .left: return (-m, 0)
        case .right: return (m, 0)
        }
    }
}

public enum MouseAction: Codable, Hashable, Sendable {
    case click(MouseButton)         // press on down, release on up (natural hold)
    case doubleClick(MouseButton)   // double-click on press
    /// Scroll in a direction while held. `speed` = base units/tick; `accelerate`
    /// ramps the speed up the longer the key is held.
    case scroll(direction: MouseDirection, speed: Double, accelerate: Bool)
    /// Move the cursor in a direction while held (same speed/accelerate semantics).
    case move(direction: MouseDirection, speed: Double, accelerate: Bool)
}

/// Media / system keys, synthesized via the systemDefined NSEvent technique.
public enum MediaKey: String, Codable, Hashable, Sendable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    public var displayName: String {
        switch self {
        case .playPause: return "Play / Pause"
        case .next: return "Next Track"
        case .previous: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        }
    }

    /// NX_KEYTYPE_* code used in the systemDefined event's data1.
    public var nxKeyType: Int {
        switch self {
        case .volumeUp: return 0      // NX_KEYTYPE_SOUND_UP
        case .volumeDown: return 1    // NX_KEYTYPE_SOUND_DOWN
        case .mute: return 7          // NX_KEYTYPE_MUTE
        case .playPause: return 16    // NX_KEYTYPE_PLAY
        case .next: return 17         // NX_KEYTYPE_NEXT
        case .previous: return 18     // NX_KEYTYPE_PREVIOUS
        }
    }
}

/// Frontmost-window tiling, performed via the Accessibility API.
public enum WindowAction: String, Codable, Hashable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center, restore

    public var displayName: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top-Left Quarter"
        case .topRight: return "Top-Right Quarter"
        case .bottomLeft: return "Bottom-Left Quarter"
        case .bottomRight: return "Bottom-Right Quarter"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore Size"
        }
    }
}

/// System commands. Most are a single keystroke; `sleepDisplay` is special-cased.
public enum SystemCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case missionControl, appWindows, spaceLeft, spaceRight, showDesktop
    case fullscreen, minimize, hideApp
    case zoomIn, zoomOut, zoomReset
    case screenshotRegion, screenshotFull, screenshotUI
    case lockScreen, sleepDisplay

    public var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appWindows: return "App Windows"
        case .spaceLeft: return "Space ← (left)"
        case .spaceRight: return "Space → (right)"
        case .showDesktop: return "Show Desktop"
        case .fullscreen: return "Toggle Full Screen"
        case .minimize: return "Minimize Window"
        case .hideApp: return "Hide App"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .zoomReset: return "Reset Zoom"
        case .screenshotRegion: return "Screenshot (Region)"
        case .screenshotFull: return "Screenshot (Full)"
        case .screenshotUI: return "Screenshot (Tools)"
        case .lockScreen: return "Lock Screen"
        case .sleepDisplay: return "Sleep Display"
        }
    }

    public var group: String {
        switch self {
        case .missionControl, .appWindows, .spaceLeft, .spaceRight, .showDesktop: return "Spaces"
        case .fullscreen, .minimize, .hideApp: return "Window"
        case .zoomIn, .zoomOut, .zoomReset: return "Zoom"
        case .screenshotRegion, .screenshotFull, .screenshotUI: return "Screenshot"
        case .lockScreen, .sleepDisplay: return "System"
        }
    }

    /// CoreDock notification for commands that macOS won't trigger from a
    /// synthesized hotkey (Mission Control / App Windows / Show Desktop).
    public var coreDockNotification: String? {
        switch self {
        case .missionControl: return "com.apple.expose.awake"
        case .appWindows: return "com.apple.expose.front.awake"
        case .showDesktop: return "com.apple.showdesktop.awake"
        default: return nil
        }
    }

    /// The keystroke that triggers this command, or nil for special handling.
    public var keyChord: KeyChord? {
        switch self {
        case .missionControl: return KeyChord(key: "up", modifiers: [.control])
        case .appWindows: return KeyChord(key: "down", modifiers: [.control])
        case .spaceLeft: return KeyChord(key: "left", modifiers: [.control])
        case .spaceRight: return KeyChord(key: "right", modifiers: [.control])
        case .showDesktop: return KeyChord(key: "f11", modifiers: [.function])
        case .fullscreen: return KeyChord(key: "f", modifiers: [.control, .command])
        case .minimize: return KeyChord(key: "m", modifiers: [.command])
        case .hideApp: return KeyChord(key: "h", modifiers: [.command])
        case .zoomIn: return KeyChord(key: "equal", modifiers: [.command])  // ⌘= (layout adds shift on JIS)
        case .zoomOut: return KeyChord(key: "minus", modifiers: [.command])
        case .zoomReset: return KeyChord(key: "0", modifiers: [.command])
        case .screenshotRegion: return KeyChord(key: "4", modifiers: [.command, .shift])
        case .screenshotFull: return KeyChord(key: "3", modifiers: [.command, .shift])
        case .screenshotUI: return KeyChord(key: "5", modifiers: [.command, .shift])
        case .lockScreen: return KeyChord(key: "q", modifiers: [.control, .command])
        case .sleepDisplay: return nil
        }
    }
}

public enum BindingAction: Codable, Hashable, Sendable {
    case none
    case keystroke(KeyChord)
    case text(String)
    case mouse(MouseAction)
    case macro(UUID)
    case media(MediaKey)
    case window(WindowAction)
    case system(SystemCommand)
    case launchApp(bundleID: String, name: String, args: [String])
    case openURL(String)
    case runShortcut(String)

    public var summary: String {
        switch self {
        case .none: return "—"
        case .keystroke(let c):
            return ModifierSet.symbols(c.modifiers) + KeyCodeTable.label(for: c.key)
        case .text(let s): return "Type “\(s.prefix(16))\(s.count > 16 ? "…" : "")”"
        case .mouse(let m): return m.summary
        case .macro: return "Macro"
        case .media(let m): return m.displayName
        case .window(let w): return w.displayName
        case .system(let s): return s.displayName
        case .launchApp(_, let name, let args): return args.isEmpty ? "Open \(name)" : "Open \(name) (+args)"
        case .openURL(let u): return "Open \(u.prefix(18))\(u.count > 18 ? "…" : "")"
        case .runShortcut(let n): return "Shortcut: \(n)"
        }
    }
}

extension BindingAction {
    /// Explicit Codable that reproduces Swift's *synthesized* enum format exactly
    /// (`{"<case>": {"_0": value}}`, labeled payload for `launchApp`) so every
    /// existing on-disk binding keeps decoding, while letting `launchApp.args` be
    /// optional (older configs had no `args`). Hand-rolled — not synthesized —
    /// because adding `args` to the synthesized form would break old decodes and
    /// `LenientBindings` would silently drop those bindings.
    private enum CaseKey: String, CodingKey {
        case none, keystroke, text, mouse, macro, media, window, system, launchApp, openURL, runShortcut
    }
    private enum Box: String, CodingKey { case _0 }
    private enum LaunchKey: String, CodingKey { case bundleID, name, args }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKey.self)
        func boxed<T: Decodable>(_ key: CaseKey, _ type: T.Type) throws -> T {
            try c.nestedContainer(keyedBy: Box.self, forKey: key).decode(T.self, forKey: ._0)
        }
        if c.contains(.keystroke) { self = .keystroke(try boxed(.keystroke, KeyChord.self)) }
        else if c.contains(.text) { self = .text(try boxed(.text, String.self)) }
        else if c.contains(.mouse) { self = .mouse(try boxed(.mouse, MouseAction.self)) }
        else if c.contains(.macro) { self = .macro(try boxed(.macro, UUID.self)) }
        else if c.contains(.media) { self = .media(try boxed(.media, MediaKey.self)) }
        else if c.contains(.window) { self = .window(try boxed(.window, WindowAction.self)) }
        else if c.contains(.system) { self = .system(try boxed(.system, SystemCommand.self)) }
        else if c.contains(.launchApp) {
            let b = try c.nestedContainer(keyedBy: LaunchKey.self, forKey: .launchApp)
            self = .launchApp(bundleID: try b.decode(String.self, forKey: .bundleID),
                              name: try b.decode(String.self, forKey: .name),
                              args: try b.decodeIfPresent([String].self, forKey: .args) ?? [])
        }
        else if c.contains(.openURL) { self = .openURL(try boxed(.openURL, String.self)) }
        else if c.contains(.runShortcut) { self = .runShortcut(try boxed(.runShortcut, String.self)) }
        else if c.contains(.none) { self = .none }
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Unknown BindingAction case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKey.self)
        func box<T: Encodable>(_ key: CaseKey, _ value: T) throws {
            var b = c.nestedContainer(keyedBy: Box.self, forKey: key)
            try b.encode(value, forKey: ._0)
        }
        switch self {
        case .none: _ = c.nestedContainer(keyedBy: Box.self, forKey: .none)
        case .keystroke(let v): try box(.keystroke, v)
        case .text(let v): try box(.text, v)
        case .mouse(let v): try box(.mouse, v)
        case .macro(let v): try box(.macro, v)
        case .media(let v): try box(.media, v)
        case .window(let v): try box(.window, v)
        case .system(let v): try box(.system, v)
        case .launchApp(let id, let name, let args):
            var b = c.nestedContainer(keyedBy: LaunchKey.self, forKey: .launchApp)
            try b.encode(id, forKey: .bundleID)
            try b.encode(name, forKey: .name)
            try b.encode(args, forKey: .args)
        case .openURL(let v): try box(.openURL, v)
        case .runShortcut(let v): try box(.runShortcut, v)
        }
    }
}

// MARK: - Banks & profiles

public struct RGBColor: Codable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    public static let off = RGBColor(r: 0, g: 0, b: 0)
}

public struct Bank: Hashable, Sendable {
    public var name: String
    public var color: RGBColor
    /// Sparse map; a missing input means `.none`.
    public var bindings: [InputID: BindingAction]

    public init(name: String, color: RGBColor, bindings: [InputID: BindingAction] = [:]) {
        self.name = name
        self.color = color
        self.bindings = bindings
    }

    public func binding(for id: InputID) -> BindingAction { bindings[id] ?? .none }
}

extension Bank: Codable {
    enum CodingKeys: String, CodingKey { case name, color, bindings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(RGBColor.self, forKey: .color)
        // Decode bindings leniently: an entry that fails (e.g. from an older
        // schema) is dropped rather than failing the whole config.
        bindings = (try? c.decode(LenientBindings.self, forKey: .bindings))?.value ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(color, forKey: .color)
        try c.encode(LenientBindings(bindings), forKey: .bindings)
    }
}

/// `[InputID: BindingAction]` as a JSON object keyed by input raw value, where
/// individual entries that fail to decode are skipped (forward/backward-compatible).
struct LenientBindings: Codable {
    var value: [InputID: BindingAction]
    init(_ value: [InputID: BindingAction]) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: G13CodingKey.self)
        var result: [InputID: BindingAction] = [:]
        for key in c.allKeys {
            guard let id = InputID(rawValue: key.stringValue) else { continue }
            if let action = try? c.decode(BindingAction.self, forKey: key) {
                result[id] = action
            }
        }
        value = result
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: G13CodingKey.self)
        for (id, action) in value {
            try c.encode(action, forKey: G13CodingKey(stringValue: id.rawValue))
        }
    }
}

public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var banks: [Bank]               // exactly 4 (M1/M2/M3/MR)
    public var lastActiveBankIndex: Int

    public init(id: UUID = UUID(), name: String, banks: [Bank], lastActiveBankIndex: Int = 0) {
        self.id = id
        self.name = name
        self.banks = banks
        self.lastActiveBankIndex = lastActiveBankIndex
    }
}

public struct AppAssociation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var bundleIdentifier: String
    public var profileID: UUID

    public init(id: UUID = UUID(), bundleIdentifier: String, profileID: UUID) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.profileID = profileID
    }
}

// MARK: - Macros

/// One step in a macro: a full `BindingAction`, the pause after it runs, and an
/// enable flag. A "Wait" step is `action == .none` with `delayAfterMs > 0`.
public struct MacroStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var action: BindingAction
    public var delayAfterMs: Int
    public var isEnabled: Bool

    public init(id: UUID = UUID(), action: BindingAction,
                delayAfterMs: Int = 60, isEnabled: Bool = true) {
        self.id = id
        self.action = action
        self.delayAfterMs = delayAfterMs
        self.isEnabled = isEnabled
    }
}

/// Pre-RPA macro step format (low-level key down/up + delay). Kept only so old
/// configs and the keystroke recorder can be migrated into `MacroStep`.
public enum LegacyMacroStep: Codable, Hashable, Sendable {
    case key(name: KeyName, down: Bool, modifiers: ModifierSet)
    case text(String)
    case mouse(MouseAction)
    case delay(milliseconds: Int)
}

public struct Macro: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [MacroStep]
    public var repeatCount: Int

    public init(id: UUID = UUID(), name: String, steps: [MacroStep] = [], repeatCount: Int = 1) {
        self.id = id
        self.name = name
        self.steps = steps
        self.repeatCount = repeatCount
    }
}

extension Macro: Codable {
    enum CodingKeys: String, CodingKey { case id, name, steps, repeatCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        // Prefer the new step shape; fall back to migrating legacy steps. The two
        // shapes are disjoint (new requires `id`, legacy requires a case key).
        if let new = try? c.decode([MacroStep].self, forKey: .steps) {
            steps = new
        } else if let legacy = try? c.decode([LegacyMacroStep].self, forKey: .steps) {
            steps = Macro.migrate(legacy)
        } else {
            steps = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(steps, forKey: .steps)
        try c.encode(repeatCount, forKey: .repeatCount)
    }

    /// Collapse legacy key down/up pairs into single keystroke taps and fold
    /// `delay` steps into the preceding step's `delayAfterMs`.
    public static func migrate(_ legacy: [LegacyMacroStep]) -> [MacroStep] {
        var out: [MacroStep] = []
        for step in legacy {
            switch step {
            case .key(let name, let down, let mods):
                if down { out.append(MacroStep(action: .keystroke(KeyChord(key: name, modifiers: mods)))) }
                // key-up is dropped — the down already emits a complete tap.
            case .text(let s):
                out.append(MacroStep(action: .text(s)))
            case .mouse(let m):
                out.append(MacroStep(action: .mouse(m)))
            case .delay(let ms):
                if out.isEmpty {
                    out.append(MacroStep(action: .none, delayAfterMs: max(0, ms)))
                } else {
                    out[out.count - 1].delayAfterMs += max(0, ms)
                }
            }
        }
        return out
    }
}

// MARK: - Settings

public struct JoystickSettings: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case directionalKeys    // joystick → joyUp/Down/Left/Right bindings
        case mouseMove          // joystick → cursor movement
        case scrollWheel        // joystick → scroll (Y vertical, X horizontal)
        case disabled

        public var displayName: String {
            switch self {
            case .directionalKeys: return "Directional Keys"
            case .mouseMove: return "Mouse Move"
            case .scrollWheel: return "Scroll Wheel"
            case .disabled: return "Disabled"
            }
        }
    }

    public var mode: Mode
    public var deadzone: UInt8          // distance from center to activate
    public var center: UInt8            // calibrated resting value
    public var mouseSpeed: Double       // px/tick at full deflection (mouseMove)
    public var scrollSpeed: Double      // scroll units/tick at full deflection (scrollWheel)
    public var invertX: Bool
    public var invertY: Bool

    public init(mode: Mode = .directionalKeys, deadzone: UInt8 = 40, center: UInt8 = 128,
                mouseSpeed: Double = 8, scrollSpeed: Double = 3,
                invertX: Bool = false, invertY: Bool = false) {
        self.mode = mode
        self.deadzone = deadzone
        self.center = center
        self.mouseSpeed = mouseSpeed
        self.scrollSpeed = scrollSpeed
        self.invertX = invertX
        self.invertY = invertY
    }
}

/// Hold-to-repeat acceleration for mouse scroll/move (the "Accelerate while held"
/// option). `rampSeconds` = how long until top speed; `maxMultiplier` = top speed.
public struct AccelerationSettings: Hashable, Sendable {
    public var rampSeconds: Double
    public var maxMultiplier: Double

    public init(rampSeconds: Double = 5, maxMultiplier: Double = 6) {
        self.rampSeconds = rampSeconds
        self.maxMultiplier = maxMultiplier
    }
}

extension AccelerationSettings: Codable {
    enum CodingKeys: String, CodingKey { case rampSeconds, maxMultiplier }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rampSeconds = try c.decodeIfPresent(Double.self, forKey: .rampSeconds) ?? 5
        maxMultiplier = try c.decodeIfPresent(Double.self, forKey: .maxMultiplier) ?? 6
    }
}

public struct GlobalSettings: Hashable, Sendable {
    public var masterEnabled: Bool
    public var openAtLogin: Bool
    public var joystick: JoystickSettings
    public var scrollAcceleration: AccelerationSettings

    public init(masterEnabled: Bool = true, openAtLogin: Bool = false,
                joystick: JoystickSettings = JoystickSettings(),
                scrollAcceleration: AccelerationSettings = AccelerationSettings()) {
        self.masterEnabled = masterEnabled
        self.openAtLogin = openAtLogin
        self.joystick = joystick
        self.scrollAcceleration = scrollAcceleration
    }
}

extension GlobalSettings: Codable {
    enum CodingKeys: String, CodingKey { case masterEnabled, openAtLogin, joystick, scrollAcceleration }
    // Tolerant of missing keys so adding fields never invalidates an existing config.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        masterEnabled = try c.decodeIfPresent(Bool.self, forKey: .masterEnabled) ?? true
        openAtLogin = try c.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? false
        joystick = try c.decodeIfPresent(JoystickSettings.self, forKey: .joystick) ?? JoystickSettings()
        scrollAcceleration = try c.decodeIfPresent(AccelerationSettings.self, forKey: .scrollAcceleration) ?? AccelerationSettings()
    }
}

// MARK: - Root document

public struct Config: Codable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var profiles: [Profile]
    public var apps: [AppAssociation]
    public var defaultProfileID: UUID
    public var macros: [Macro]
    public var settings: GlobalSettings

    public init(schemaVersion: Int = Config.currentSchemaVersion,
                profiles: [Profile], apps: [AppAssociation] = [],
                defaultProfileID: UUID, macros: [Macro] = [],
                settings: GlobalSettings = GlobalSettings()) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
        self.apps = apps
        self.defaultProfileID = defaultProfileID
        self.macros = macros
        self.settings = settings
    }

    public func profile(id: UUID) -> Profile? { profiles.first { $0.id == id } }
    public func macro(id: UUID) -> Macro? { macros.first { $0.id == id } }

    /// Profile that applies to the given frontmost bundle id, or the default.
    public func profile(forBundleID bundleID: String?) -> Profile {
        if let bundleID, let assoc = apps.first(where: { $0.bundleIdentifier == bundleID }),
           let p = profile(id: assoc.profileID) {
            return p
        }
        return profile(id: defaultProfileID) ?? profiles[0]
    }
}

// MARK: - InputID as a JSON object key

/// Lets `[InputID: BindingAction]` encode as a JSON object (keyed by the input's
/// raw value) instead of a flat key/value array.
extension InputID: CodingKeyRepresentable {
    public var codingKey: CodingKey { G13CodingKey(stringValue: rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }
}

public struct G13CodingKey: CodingKey {
    public var stringValue: String
    public var intValue: Int? { nil }
    public init(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}

// MARK: - Display helpers

extension ModifierSet {
    public static func symbols(_ m: ModifierSet) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        if m.contains(.function) { s += "fn " }
        return s
    }
}

extension MouseAction {
    public var summary: String {
        switch self {
        case .click(let b): return "\(b.rawValue.capitalized) click"
        case .doubleClick(let b): return "\(b.rawValue.capitalized) double-click"
        case .scroll(let d, _, let a): return "Scroll \(d.displayName)\(a ? " (accel)" : "")"
        case .move(let d, _, let a): return "Move \(d.displayName)\(a ? " (accel)" : "")"
        }
    }
}
