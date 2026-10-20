import Foundation
import Observation

/// Main-actor orchestrator. Owns all services, holds the live config, resolves
/// the active profile/bank, and routes device input to injected actions.
/// `@Observable` so SwiftUI views update when state changes.
@MainActor
@Observable
public final class AppController {
    // Observable state for the UI
    public private(set) var config: Config
    public private(set) var deviceConnected = false
    public private(set) var currentBundleID: String?
    public private(set) var activeProfileName: String = ""
    public private(set) var activeProfileID: UUID
    public private(set) var activeBankIndex: Int = 0
    public private(set) var inputMonitoringGranted = false
    public private(set) var accessibilityGranted = false
    public private(set) var isRecording = false

    // Live diagnostics for the Tester view
    public private(set) var reportsReceived = 0
    public private(set) var lastReportHex = "—"
    public private(set) var lastEventText = "—"
    public private(set) var lastActionText = "—"
    public private(set) var injectionCount = 0

    // Services
    private let store: ConfigStore
    private let device = G13Device()
    private let tracker = InputStateTracker()
    private let engine = ActionEngine()
    private let focus = AppFocusMonitor()
    private let backlight: BacklightController
    private let joystick: JoystickDriver
    private let recorder = MacroRecorder()

    private var resolved: ResolvedState
    private var started = false

    public init(store: ConfigStore = ConfigStore()) {
        let cfg = store.load()
        self.store = store
        self.config = cfg
        self.activeProfileID = cfg.defaultProfileID
        self.backlight = BacklightController(device: device)
        self.joystick = JoystickDriver(engine: engine)
        self.resolved = ProfileResolver.resolve(config: cfg, bundleID: nil, bankOverride: nil)
        self.activeBankIndex = resolved.bankIndex
        self.activeProfileName = resolved.profileName
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true

        refreshPermissions()

        engine.macroProvider = { [weak self] id in self?.config.macro(id: id) }
        joystick.settings = config.settings.joystick
        applyEngineSettings()
        joystick.onDirection = { [weak self] edge in self?.handleJoyDirection(edge) }
        focus.onChange = { [weak self] bundleID in self?.handleFocusChange(bundleID) }

        // HID reports arrive on the device thread; hop to main (FIFO) for
        // decode → edge-detection → dispatch so all state stays main-isolated.
        device.onInputReport = { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let frame = InputDecoder.decode(data) else { return }
                self.handle(self.tracker.process(frame))
            }
        }
        device.onRawReport = { [weak self] reportID, bytes in
            DispatchQueue.main.async {
                guard let self else { return }
                self.reportsReceived += 1
                if reportID == 1 {
                    self.lastReportHex = bytes.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
                }
            }
        }
        device.onConnected = { [weak self] in
            DispatchQueue.main.async { self?.handleConnected() }
        }
        device.onDisconnected = { [weak self] in
            DispatchQueue.main.async { self?.deviceConnected = false }
        }

        device.start()
        focus.start()   // fires initial focus → resolves + applies backlight
    }

    public func stop() {
        device.stop()
        focus.stop()
        engine.cancelAll()
        joystick.reset()
    }

    public func refreshPermissions() {
        let wasInputMonitoring = inputMonitoringGranted
        inputMonitoringGranted = Permissions.inputMonitoringGranted()
        accessibilityGranted = Permissions.accessibilityGranted()
        // HID delivery only begins after a fresh open once permission exists, so
        // restart the device when Input Monitoring is granted while running.
        if started, !wasInputMonitoring, inputMonitoringGranted {
            Log.app.info("Input Monitoring granted while running — restarting HID")
            device.restart()
        }
    }

    // MARK: - Input handling (main actor)

    private func handle(_ events: [InputEvent]) {
        guard config.settings.masterEnabled else { return }
        for event in events {
            switch event {
            case .down(let id):
                fire(resolved.binding(for: id), edge: .down, input: id, label: "down \(id.displayName)")
            case .up(let id):
                fire(resolved.binding(for: id), edge: .up, input: id, label: "up \(id.displayName)")
            case .bankKey(let m):
                lastEventText = "bank \(m.displayName)"
                selectBank(m.bankIndex)
            case .joystick(let x, let y):
                joystick.update(x: x, y: y)
            }
        }
    }

    private func handleJoyDirection(_ edge: JoystickDriver.DirectionEdge) {
        guard config.settings.masterEnabled else { return }
        switch edge {
        case .down(let id): fire(resolved.binding(for: id), edge: .down, input: id, label: "down \(id.displayName)")
        case .up(let id): fire(resolved.binding(for: id), edge: .up, input: id, label: "up \(id.displayName)")
        }
    }

    /// Inject a binding and update diagnostics.
    private func fire(_ action: BindingAction, edge: ActionEngine.Edge, input: InputID, label: String) {
        lastEventText = label
        if edge == .down {
            lastActionText = action.summary
            if case .none = action {} else { injectionCount += 1 }
        }
        engine.perform(action, edge: edge, input: input)
    }

    private func handleConnected() {
        deviceConnected = true
        applyBacklight()
    }

    private func handleFocusChange(_ bundleID: String?) {
        currentBundleID = bundleID
        let profile = config.profile(forBundleID: bundleID)
        activeProfileID = profile.id
        activeBankIndex = min(max(0, profile.lastActiveBankIndex), 3)
        // Release anything held in the previous context. A macro or key sequence
        // under way keeps going into the new app (it may have opened it) — unless
        // that app is this one, where its keys would edit the settings.
        if let bundleID, bundleID == Bundle.main.bundleIdentifier {
            engine.cancelAll()
        } else {
            engine.releaseHeld()
        }
        joystick.reset()
        resolveBindings()
        applyBacklight()
    }

    // MARK: - Banks

    public func selectBank(_ index: Int) {
        let idx = min(max(0, index), 3)
        activeBankIndex = idx
        if let p = config.profiles.firstIndex(where: { $0.id == activeProfileID }) {
            config.profiles[p].lastActiveBankIndex = idx
            try? store.save(config)
        }
        engine.cancelAll()
        joystick.reset()
        resolveBindings()
        applyBacklight()
    }

    private func resolveBindings() {
        resolved = ProfileResolver.resolve(config: config, bundleID: currentBundleID, bankOverride: activeBankIndex)
        activeProfileName = resolved.profileName
    }

    private func applyBacklight() {
        guard deviceConnected else { return }
        backlight.setColor(resolved.bankColor)
        backlight.setBankLED(activeBankIndex)
    }

    private func applyEngineSettings() {
        engine.accelerationRampSeconds = config.settings.scrollAcceleration.rampSeconds
        engine.accelerationMax = config.settings.scrollAcceleration.maxMultiplier
    }

    // MARK: - Config editing (from the GUI)

    /// Replace the whole config, persist, and re-apply live.
    public func apply(_ newConfig: Config) {
        config = newConfig
        try? store.save(config)
        engine.macroProvider = { [weak self] id in self?.config.macro(id: id) }
        joystick.settings = config.settings.joystick
        applyEngineSettings()
        engine.cancelAll()                   // an edit (or disabling) stops anything in flight
        handleFocusChange(currentBundleID)   // recompute active profile/bank + backlight
    }

    public func setMasterEnabled(_ on: Bool) {
        var c = config
        c.settings.masterEnabled = on
        apply(c)
    }

    // MARK: - Export / import

    public func exportConfig(to url: URL) throws {
        try ConfigStore.export(config, to: url)
    }

    /// Replace the whole config with `imported` (from `ConfigStore.readImport`).
    /// The current config is copied to `ConfigStore.preImportURL` first, and
    /// `openAtLogin` keeps this Mac's value — it mirrors a login item registered
    /// here, not something a settings file can turn on.
    public func importConfig(_ imported: Config) throws {
        try store.savePreImportCopy(config)
        var c = imported
        c.settings.openAtLogin = config.settings.openAtLogin
        apply(c)
    }

    // MARK: - Macro recording

    @discardableResult
    public func startRecording() -> Bool {
        let ok = recorder.start()
        isRecording = recorder.isRecording
        return ok
    }

    public func stopRecording(name: String) -> Macro {
        let macro = recorder.stop(name: name)
        isRecording = false
        return macro
    }

    /// Test a macro immediately (e.g. a "Run" button in the editor).
    public func play(_ macro: Macro) {
        engine.macroPlayer.play(macro)
    }

    /// Stop a macro that's currently replaying.
    public func stopMacro() {
        engine.macroPlayer.cancel()
    }

    public var isMacroPlaying: Bool { engine.macroPlayer.isPlaying }

    // MARK: - Diagnostics / self-test hooks

    /// Feed a synthetic press+release through the full resolve→inject pipeline,
    /// exactly as a real device event would (verifies stages 4–6 without hardware).
    public func simulateInput(_ id: InputID) {
        handle([.down(id), .up(id)])
    }

    /// Inject text directly (verifies CGEvent injection / Accessibility).
    public func injectTestText(_ text: String) {
        lastActionText = "test type: \(text)"
        injectionCount += 1
        engine.perform(.text(text), edge: .down, input: .g1)
    }

    // MARK: - Convenience accessors for the UI

    public var availableRunningApps: [(name: String, bundleID: String)] {
        FocusedAppList.runningApps()
    }
}
