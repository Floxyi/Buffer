import AppKit

struct SourceApplicationInfo: Sendable {
    let name: String?
    let bundleIdentifier: String?
    let bundlePath: String?
}

@MainActor
protocol ActiveApplicationProviding: AnyObject {
    var currentApplication: NSRunningApplication? { get }
    var currentApplicationInfo: SourceApplicationInfo { get }
}

@MainActor
final class ActiveApplicationMonitor: ActiveApplicationProviding {
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?

    private(set) var currentApplication: NSRunningApplication?

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            MainActor.assumeIsolated {
                self?.handleAppActivation(application)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    var currentApplicationInfo: SourceApplicationInfo {
        SourceApplicationInfo(
            name: currentApplication?.localizedName,
            bundleIdentifier: currentApplication?.bundleIdentifier,
            bundlePath: currentApplication?.bundleURL?.path
        )
    }

    private func handleAppActivation(_ application: NSRunningApplication) {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        guard application.processIdentifier != currentProcessID else {
            return
        }

        currentApplication = application
    }
}
