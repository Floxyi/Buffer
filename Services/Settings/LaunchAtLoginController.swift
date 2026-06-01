import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}
