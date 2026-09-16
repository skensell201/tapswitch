import Foundation
import ServiceManagement

/// `SMAppService` needs a real `.app`; run straight from `swift build` there
/// is none, and the menu item is disabled.
@MainActor
struct LaunchAtLogin {
    var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
