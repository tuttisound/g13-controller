import AppKit
import ApplicationServices
import G13Core

/// One-shot diagnostics (run via `--diag`) to test window tiling, character
/// injection, and menu-command keystrokes against TextEdit using the real
/// injection path, reading results back through the Accessibility API.
@MainActor
enum G13Diag {
    static func run() {
        func log(_ s: String) { fputs(s + "\n", stderr) }
        log("=== G13 diag ===")
        log("accessibility trusted: \(Permissions.accessibilityGranted())")

        // Force TextEdit frontmost via LaunchServices (more reliable than
        // NSWorkspace.openApplication from a background process).
        let openProc = Process()
        openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProc.arguments = ["-a", "TextEdit"]
        try? openProc.run()
        spin(2.5)

        guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
            log("TextEdit not running"); return
        }
        te.activate()
        spin(0.8)
        let pid = te.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
        log("TextEdit pid=\(pid); frontmost now=\(front)")

        let engine = ActionEngine()

        // Get TextEdit's window directly (by pid, not "frontmost").
        let (winStatus, window) = teWindow(app)
        log("--- test: get TextEdit window: \(winStatus) ---")

        // 1) Window tiling via direct AX set on TextEdit's window.
        if let window {
            log("before: \(frame(window))")
            WindowManager.shared.perform(.leftHalf)   // acts on frontmost
            spin(0.6)
            log("after WindowManager.leftHalf (frontmost): \(frame(window))")
            // Also directly set the frame via AX to isolate the AX-control path:
            directSetLeftHalf(window)
            spin(0.4)
            log("after direct AX set left-half: \(frame(window))")
        }

        // 2) Character injection: shift+equal should type "+" (only valid if TextEdit is frontmost).
        if front == "com.apple.TextEdit" {
            log("--- test: type '=' (key 'equal', layout-aware → should be '=') ---")
            engine.perform(.keystroke(KeyChord(key: "equal")), edge: .down, input: .g1)
            engine.perform(.keystroke(KeyChord(key: "equal")), edge: .up, input: .g1)
            spin(0.4)
            log("focused text value: '\(focusedValue(app) ?? "nil")'")

            // 3) Menu command: Minimize (⌘M).
            log("--- test: Minimize (cmd+m) ---")
            engine.perform(.system(.minimize), edge: .down, input: .g1)
            spin(0.6)
            if let window { log("window minimized = \(boolAttr(window, kAXMinimizedAttribute))") }
        } else {
            log("(skipping keystroke tests — TextEdit not frontmost)")
        }

        log("=== done ===")
    }

    private static func teWindow(_ app: AXUIElement) -> (String, AXUIElement?) {
        // Try focused window, then first of the windows list.
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() {
            return ("focused", (ref as! AXUIElement))
        }
        var wins: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins) == .success,
           let arr = wins as? [AXUIElement], let first = arr.first {
            return ("windows[0]", first)
        }
        return ("none", nil)
    }

    private static func directSetLeftHalf(_ window: AXUIElement) {
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        // left half in Cocoa coords:
        let cocoa = CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        var pos = CGPoint(x: cocoa.minX, y: primaryH - cocoa.minY - cocoa.height)
        var size = CGSize(width: cocoa.width, height: cocoa.height)
        if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
    }

    private static func focusedValue(_ app: AXUIElement) -> String? {
        var f: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success,
              let f, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(f as! AXUIElement, kAXValueAttribute as CFString, &v)
        return v as? String
    }

    private static func frame(_ window: AXUIElement) -> String {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let posRef { AXValueGetValue(posRef as! AXValue, .cgPoint, &pos) }
        if let sizeRef { AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) }
        return "pos=(\(Int(pos.x)),\(Int(pos.y))) size=(\(Int(size.width))x\(Int(size.height)))"
    }

    private static func boolAttr(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "?" }
        return "\((v as? Bool).map(String.init) ?? "?")"
    }

    private static func spin(_ s: TimeInterval) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: s))
    }
}
