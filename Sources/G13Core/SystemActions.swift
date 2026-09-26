import Foundation
import AppKit

/// App launch/activate, opening URLs/files, running Shortcuts, and display sleep.
/// None of these need a TCC permission beyond what the app already has.
public enum SystemActions {
    /// Launch the app, or bring it to the front if already running. `args` are
    /// passed as launch arguments (e.g. Chrome `--profile-directory=… --new-window <url>`);
    /// they take effect on a fresh launch / relaunch.
    public static func launchOrActivate(bundleID: String, args: [String] = []) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Log.action.error("launchApp: no app for bundle id \(bundleID, privacy: .public)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if !args.isEmpty { config.arguments = args }
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                Log.action.error("launchApp failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Open a web URL (has a scheme) or a file/folder path.
    public static func openURLOrFile(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
        } else {
            let path = (trimmed as NSString).expandingTildeInPath
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    public static func runShortcut(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        runTool("/usr/bin/shortcuts", ["run", trimmed])
    }

    public static func sleepDisplay() {
        runTool("/usr/bin/pmset", ["displaysleepnow"])
    }

    /// Switch Mission Control space left/right. CGEvent-synthesized ⌃←/→ are
    /// blocked by WindowServer, but routing the keystroke through System Events
    /// (an Apple-signed process) via AppleScript passes the gate. Requires
    /// Automation permission for System Events (prompted on first use), the
    /// default ⌃←/→ shortcuts enabled, and more than one desktop.
    public static func switchSpace(left: Bool) {
        runAppleScript("tell application \"System Events\" to key code \(left ? 123 : 124) using control down")
    }

    /// Zoom in via System Events so the correct "+" character is produced for the
    /// current keyboard layout. (CGEvent + an ANSI keycode types the wrong symbol
    /// on JIS, and AppKit menu matching ignores shift, so ⌘= can't be synthesized
    /// reliably there.) Reuses the System Events Automation permission.
    public static func zoomIn() {
        runAppleScript("tell application \"System Events\" to keystroke \"+\" using command down")
    }

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            Log.action.error("AppleScript: \(String(describing: error[NSAppleScript.errorMessage]), privacy: .public)")
        }
    }

    private static func runTool(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        do {
            try process.run()
        } catch {
            Log.action.error("\(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Private CoreDock trigger for Mission Control / App Exposé / Show Desktop,
/// which macOS does not trigger from synthesized hotkeys on recent versions.
enum CoreDock {
    private typealias SendFn = @convention(c) (CFString, Int32) -> Void

    private static let sendFn: SendFn? = {
        // CoreDockSendNotification is exported by the public Carbon umbrella
        // framework (CoreDock.framework itself isn't dlopen-able on Tahoe).
        let paths = [
            "/System/Library/Frameworks/Carbon.framework/Carbon",
            "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon",
        ]
        for path in paths {
            if let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, "CoreDockSendNotification") {
                return unsafeBitCast(sym, to: SendFn.self)
            }
        }
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CoreDockSendNotification") {  // RTLD_DEFAULT
            return unsafeBitCast(sym, to: SendFn.self)
        }
        return nil
    }()

    @discardableResult
    static func send(_ notification: String) -> Bool {
        guard let fn = sendFn else {
            Log.action.error("CoreDockSendNotification unavailable")
            return false
        }
        fn(notification as CFString, 0)
        return true
    }
}
