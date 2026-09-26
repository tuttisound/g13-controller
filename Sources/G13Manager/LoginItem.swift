import Foundation
import ServiceManagement
import G13Core

/// Open-at-login via SMAppService (registers the .app itself). Only meaningful
/// for the packaged app; harmless if it fails when run as a bare binary.
enum LoginItem {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.app.error("Open-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
