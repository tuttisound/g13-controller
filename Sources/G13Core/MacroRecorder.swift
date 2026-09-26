import Foundation
import CoreGraphics

/// Records a sequence of keystrokes with inter-event timing via a listen-only
/// `CGEventTap` on the main runloop. Events we injected ourselves (tagged by
/// `EventTagger`) are ignored so a macro can't record its own playback.
///
/// Capture is in the low-level `LegacyMacroStep` form (key down/up + delay);
/// `stop()` migrates it into the RPA `MacroStep` shape.
///
/// Used on the main thread (the tap is attached to the main runloop).
public final class MacroRecorder {
    public private(set) var isRecording = false
    /// Optional live callback as steps are captured (for GUI feedback).
    public var onStep: ((LegacyMacroStep) -> Void)?

    private let tagger: EventTagger
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var steps: [LegacyMacroStep] = []
    private var lastTime: CFAbsoluteTime?

    public init(tagger: EventTagger = .shared) { self.tagger = tagger }

    /// Begin recording. Returns false if the event tap couldn't be created
    /// (usually missing Accessibility/Input Monitoring permission).
    @discardableResult
    public func start() -> Bool {
        guard !isRecording else { return true }
        steps = []
        lastTime = nil

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<MacroRecorder>.fromOpaque(refcon).takeUnretainedValue()
                        .handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.action.error("MacroRecorder: failed to create event tap (permissions?)")
            return false
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRecording = true
        return true
    }

    /// Stop recording and return the captured macro (migrated to `MacroStep`).
    @discardableResult
    public func stop(name: String = "Recorded Macro") -> Macro {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRecording = false
        return Macro(name: name, steps: Macro.migrate(steps))
    }

    public var currentSteps: [LegacyMacroStep] { steps }

    private func handle(type: CGEventType, event: CGEvent) {
        if tagger.isOurs(event) { return }                 // skip our own injected events
        guard type == .keyDown || type == .keyUp else { return }

        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let name = KeyCodeTable.name(for: code) else { return }
        let mods = Self.modifiers(from: event.flags)

        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastTime {
            let ms = Int((now - last) * 1000)
            if ms > 5 {
                let delay = LegacyMacroStep.delay(milliseconds: min(ms, 5000))
                steps.append(delay)
                onStep?(delay)
            }
        }
        lastTime = now

        let step = LegacyMacroStep.key(name: name, down: type == .keyDown, modifiers: mods)
        steps.append(step)
        onStep?(step)
    }

    private static func modifiers(from flags: CGEventFlags) -> ModifierSet {
        var m: ModifierSet = []
        if flags.contains(.maskCommand) { m.insert(.command) }
        if flags.contains(.maskShift) { m.insert(.shift) }
        if flags.contains(.maskAlternate) { m.insert(.option) }
        if flags.contains(.maskControl) { m.insert(.control) }
        if flags.contains(.maskSecondaryFn) { m.insert(.function) }
        return m
    }
}
