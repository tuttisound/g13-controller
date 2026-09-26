import AppKit
import G13Core

// Menu-bar agent entry point. Using an AppKit bootstrap (rather than a SwiftUI
// `App`) is the most reliable way to run a status-bar app built with SwiftPM and
// no Xcode. The window content is SwiftUI, hosted via NSHostingController.

let arguments = CommandLine.arguments

// Headless self-test: inject a marker string into the frontmost app, then exit.
// Used to verify CGEvent injection (Accessibility) without the device.
//   G13Manager --selftest-inject [text]
if arguments.contains("--selftest-inject") {
    MainActor.assumeIsolated {
        let text = arguments.last.flatMap { $0.hasPrefix("--") ? nil : $0 } ?? "G13_INJECT_OK "
        fputs("[selftest] accessibility granted: \(Permissions.accessibilityGranted())\n", stderr)
        let engine = ActionEngine()
        fputs("[selftest] focusing target for 1.5s…\n", stderr)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.5))
        fputs("[selftest] injecting: \(text)\n", stderr)
        engine.perform(.text(text), edge: .down, input: .g1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        fputs("[selftest] done\n", stderr)
    }
    exit(0)
}

if arguments.contains("--diag") {
    MainActor.assumeIsolated { G13Diag.run() }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon by default (menu-bar agent)
    app.run()
}
