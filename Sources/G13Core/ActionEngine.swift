import Foundation
import CoreGraphics
import AppKit

/// Turns a resolved `BindingAction` + press/release edge into injected events.
/// Also exposes low-level primitives reused by the joystick driver.
@MainActor
public final class ActionEngine {
    public enum Edge { case down, up }

    private let tagger: EventTagger
    public let macroPlayer: MacroPlayer
    /// Resolves a macro id to a `Macro` (wired to the live config by AppController).
    public var macroProvider: (UUID) -> Macro? = { _ in nil }

    private var continuousTasks: [InputID: Task<Void, Never>] = [:]
    private var heldMouseButtons: [InputID: MouseButton] = [:]
    /// Newest key sequence started by a press. Each one waits for the one before
    /// it, so a press during typing queues instead of interleaving characters.
    private var typingTask: Task<Void, Never>?

    /// Hold-to-repeat timing (initial delay before repeating, then interval).
    private let repeatInitialDelayNs: UInt64 = 350_000_000
    private let repeatIntervalNs: UInt64 = 33_000_000   // ~30/sec

    /// Mouse scroll/move "Accelerate while held" parameters (synced from config).
    public var accelerationRampSeconds: Double = 5
    public var accelerationMax: Double = 6

    public init(tagger: EventTagger = .shared) {
        self.tagger = tagger
        self.macroPlayer = MacroPlayer()
        self.macroPlayer.engine = self
    }

    // MARK: - Dispatch

    public func perform(_ action: BindingAction, edge: Edge, input: InputID) {
        switch action {
        case .none:
            break
        case .keystroke(let chord):
            performKeystroke(chord, edge: edge, input: input)
        case .text(let s):
            if edge == .down { Injector.text(s, tagger: tagger) }
        case .mouse(let m):
            performMouse(m, edge: edge, input: input)
        case .macro(let id):
            if edge == .down, let macro = macroProvider(id) { macroPlayer.play(macro) }
        case .media(let key):
            if edge == .down { Injector.mediaKey(key, tagger: tagger) }
        case .window(let w):
            if edge == .down { WindowManager.shared.perform(w) }
        case .system(let command):
            if edge == .down { performSystem(command) }
        case .launchApp(let bundleID, _, let args):
            if edge == .down { SystemActions.launchOrActivate(bundleID: bundleID, args: args) }
        case .openURL(let string):
            if edge == .down { SystemActions.openURLOrFile(string) }
        case .runShortcut(let name):
            if edge == .down { SystemActions.runShortcut(name) }
        }
    }

    /// Run an action to completion as a single discrete effect (used for macro
    /// steps): no press/hold/repeat semantics — keystroke = one tap, click = one
    /// click, scroll/move = one tick, key sequence = typed out in full before
    /// returning. Reuses the same primitives as `perform`.
    public func performOnce(_ action: BindingAction) async {
        switch action {
        case .none:
            break
        case .keystroke(let chord):
            if let sequence = chord.sequence {
                await type(sequence)
            } else if let (code, flags) = KeyCodeTable.resolve(key: chord.key, modifiers: chord.modifiers) {
                tapKey(code, flags: flags)
            }
        case .text(let s):
            Injector.text(s, tagger: tagger)
        case .mouse(let m):
            switch m {
            case .click(let b): Injector.click(b, count: 1, tagger: tagger)
            case .doubleClick(let b): Injector.click(b, count: 2, tagger: tagger)
            case .scroll(let dir, let speed, _):
                let d = dir.scrollDelta(magnitude: max(1, Int(speed)))
                Injector.scroll(dx: d.dx, dy: d.dy, tagger: tagger)
            case .move(let dir, let speed, _):
                let d = dir.moveDelta(magnitude: max(1, Int(speed)))
                Injector.move(dx: d.dx, dy: d.dy, tagger: tagger)
            }
        case .media(let key):
            Injector.mediaKey(key, tagger: tagger)
        case .window(let w):
            WindowManager.shared.perform(w)
        case .system(let command):
            performSystem(command)
        case .launchApp(let bundleID, _, let args):
            SystemActions.launchOrActivate(bundleID: bundleID, args: args)
        case .openURL(let string):
            SystemActions.openURLOrFile(string)
        case .runShortcut(let name):
            SystemActions.runShortcut(name)
        case .macro:
            break   // nested macros aren't supported as a single step
        }
    }

    private func performSystem(_ command: SystemCommand) {
        switch command {
        case .sleepDisplay:
            SystemActions.sleepDisplay()
        case .minimize:
            WindowManager.shared.minimizeFront()
        case .hideApp:
            NSWorkspace.shared.frontmostApplication?.hide()
        case .fullscreen:
            WindowManager.shared.toggleFullScreenFront()
        case .missionControl, .appWindows, .showDesktop:
            if let note = command.coreDockNotification { CoreDock.send(note) }
        case .spaceLeft:
            SystemActions.switchSpace(left: true)
        case .spaceRight:
            SystemActions.switchSpace(left: false)
        case .zoomIn:
            SystemActions.zoomIn()
        default:
            // Mostly app/web shortcuts (zoom, screenshots, lock, spaces); resolve
            // the key through the current layout so symbols work on JIS etc.
            if let chord = command.keyChord,
               let (code, flags) = KeyCodeTable.resolve(key: chord.key, modifiers: chord.modifiers) {
                tapKey(code, flags: flags)
            }
        }
    }

    /// Stop key repeats and scroll/move drives and release held mouse buttons —
    /// what a change of frontmost app needs. A running macro or key sequence
    /// keeps going: it may be what switched apps (Open App, then type into it).
    public func releaseHeld() {
        for (_, t) in continuousTasks { t.cancel() }
        continuousTasks.removeAll()
        for (_, b) in heldMouseButtons { Injector.mouseButton(b, down: false, tagger: tagger) }
        heldMouseButtons.removeAll()
    }

    /// `releaseHeld()`, and also stop any macro or key sequence (call on config
    /// edits, master-disable, bank switch, or app quit).
    public func cancelAll() {
        releaseHeld()
        typingTask?.cancel()
        typingTask = nil
        macroPlayer.cancel()
    }

    // MARK: - Low-level primitives (reused by JoystickDriver)

    public func moveMouse(dx: Int, dy: Int) { Injector.move(dx: dx, dy: dy, tagger: tagger) }
    public func scroll(dx: Int, dy: Int) { Injector.scroll(dx: dx, dy: dy, tagger: tagger) }

    // MARK: - Keystroke

    private func performKeystroke(_ chord: KeyChord, edge: Edge, input: InputID) {
        if let sequence = chord.sequence {
            // Typed out in full on press; releasing the G13 key doesn't cut it short.
            if edge == .down { enqueueTyping(sequence) }
            return
        }
        guard let (code, flags) = KeyCodeTable.resolve(key: chord.key, modifiers: chord.modifiers) else {
            Log.action.error("Unknown key: \(chord.key.rawValue, privacy: .public)")
            return
        }
        if chord.repeatsWhileHeld {
            switch edge {
            case .down:
                tapKey(code, flags: flags)                       // first character
                startKeyRepeat(input, code: code, flags: flags)  // then repeat
            case .up:
                stopContinuous(input)
            }
        } else if edge == .down {
            tapKey(code, flags: flags)
        }
    }

    /// A self-contained keypress (down+up). Repeats are emitted as repeated taps,
    /// which every app registers as a character — unlike a held keyDown with the
    /// autorepeat flag, which Cocoa/Chromium apps ignore for synthesized events.
    private func tapKey(_ code: CGKeyCode, flags: CGEventFlags) {
        Injector.key(code, down: true, flags: flags, tagger: tagger)
        Injector.key(code, down: false, flags: flags, tagger: tagger)
    }

    private func enqueueTyping(_ sequence: KeySequence) {
        let previous = typingTask
        typingTask = Task { @MainActor [weak self] in
            // Cancelling the newest sequence (cancelAll) cancels the queue behind it too.
            await withTaskCancellationHandler {
                await previous?.value
            } onCancel: {
                previous?.cancel()
            }
            guard !Task.isCancelled else { return }
            await self?.type(sequence)
        }
    }

    /// Type `sequence.text` one key tap per character, pausing `intervalMs`
    /// between characters. Real keystrokes (not a Unicode string) so the active
    /// input method and app shortcuts see ordinary typing; a character with no
    /// key on the current layout falls back to Unicode injection. Stops early
    /// when the surrounding task is cancelled.
    private func type(_ sequence: KeySequence) async {
        let pause = UInt64(min(max(0, sequence.intervalMs), KeySequence.maxIntervalMs)) * 1_000_000
        for (i, character) in sequence.text.enumerated() {
            if i > 0, pause > 0 { try? await Task.sleep(nanoseconds: pause) }
            if Task.isCancelled { return }
            if let (code, flags) = KeyCodeTable.resolve(character: character) {
                tapKey(code, flags: flags)
            } else {
                Injector.text(String(character), tagger: tagger)
            }
        }
    }

    private func startKeyRepeat(_ input: InputID, code: CGKeyCode, flags: CGEventFlags) {
        stopContinuous(input)
        let tagger = self.tagger
        let initial = repeatInitialDelayNs
        let interval = repeatIntervalNs
        continuousTasks[input] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: initial)
            while !Task.isCancelled {
                Injector.key(code, down: true, flags: flags, tagger: tagger)
                Injector.key(code, down: false, flags: flags, tagger: tagger)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    // MARK: - Mouse

    private func performMouse(_ m: MouseAction, edge: Edge, input: InputID) {
        switch m {
        case .click(let b):
            if edge == .down {
                Injector.mouseButton(b, down: true, tagger: tagger)
                heldMouseButtons[input] = b
            } else if let held = heldMouseButtons.removeValue(forKey: input) {
                Injector.mouseButton(held, down: false, tagger: tagger)
            }
        case .doubleClick(let b):
            if edge == .down { Injector.click(b, count: 2, tagger: tagger) }
        case .scroll(let dir, let speed, let accel):
            if edge == .down { startMouseDrive(input, kind: .scroll, direction: dir, speed: speed, accelerate: accel) }
            else { stopContinuous(input) }
        case .move(let dir, let speed, let accel):
            if edge == .down { startMouseDrive(input, kind: .move, direction: dir, speed: speed, accelerate: accel) }
            else { stopContinuous(input) }
        }
    }

    private enum MouseDriveKind { case scroll, move }

    /// Drive scroll/move while held at ~60Hz, optionally accelerating the longer
    /// the key is held (ramp 1x → 6x over ~5s).
    private func startMouseDrive(_ input: InputID, kind: MouseDriveKind,
                                 direction: MouseDirection, speed: Double, accelerate: Bool) {
        stopContinuous(input)
        let tagger = self.tagger
        let rampSeconds = max(0.2, accelerationRampSeconds)
        let maxMult = max(1.0, accelerationMax)
        continuousTasks[input] = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                let elapsed = Double(ticks) * 0.016   // ~60Hz tick
                let factor = accelerate ? min(maxMult, 1.0 + (elapsed / rampSeconds) * (maxMult - 1.0)) : 1.0
                let mag = max(1, Int((speed * factor).rounded()))
                switch kind {
                case .scroll:
                    let (dx, dy) = direction.scrollDelta(magnitude: mag)
                    Injector.scroll(dx: dx, dy: dy, tagger: tagger)
                case .move:
                    let (dx, dy) = direction.moveDelta(magnitude: mag)
                    Injector.move(dx: dx, dy: dy, tagger: tagger)
                }
                ticks += 1
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60Hz
            }
        }
    }

    private func stopContinuous(_ input: InputID) {
        continuousTasks[input]?.cancel()
        continuousTasks[input] = nil
    }
}
