import Foundation
import AppKit
import IOKit.hid
import ApplicationServices

/// TCC permission checks/requests for the two permissions this app needs:
/// Input Monitoring (to read HID input) and Accessibility (to post CGEvents).
public enum Permissions {
    // MARK: Input Monitoring (kTCCServiceListenEvent)

    public static func inputMonitoringGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: Accessibility (kTCCServiceAccessibility)

    public static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts once per app identity; subsequent denials are silent.
    public static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Deep links to System Settings

    public static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
