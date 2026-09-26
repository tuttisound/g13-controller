import Foundation
import AppKit

/// Watches the frontmost application and reports its bundle identifier, for
/// per-app profile auto-switching.
@MainActor
public final class AppFocusMonitor {
    public var onChange: ((String?) -> Void)?
    private var observer: NSObjectProtocol?

    public init() {}

    public var currentBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                      object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                self?.onChange?(bundleID)
            }
        }
        onChange?(currentBundleID)   // fire once for the current frontmost app
    }

    public func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}

/// Lists currently-running, user-facing apps for the GUI's app picker.
public enum FocusedAppList {
    public static func runningApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .compactMap { app in
                guard let bid = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? bid, bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
