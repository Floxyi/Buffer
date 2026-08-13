import AppKit

struct SourceApplicationInfo: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
    let bundlePath: String?

    @MainActor
    static var currentProcess: SourceApplicationInfo {
        let application = NSRunningApplication.current
        return SourceApplicationInfo(
            name: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            bundlePath: application.bundleURL?.path
        )
    }
}

@MainActor
protocol ActiveApplicationProviding: AnyObject {
    var currentApplication: NSRunningApplication? { get }
    var currentApplicationInfo: SourceApplicationInfo { get }
}

@MainActor
final class ActiveApplicationMonitor: ActiveApplicationProviding {
    private let notificationCenter: NotificationCenter
    private let frontmostApplicationProvider: @MainActor () -> NSRunningApplication?
    private let currentProcessIdentifier: pid_t
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?

    private var lastExternalApplication: NSRunningApplication?

    var currentApplication: NSRunningApplication? {
        if let frontmostApplication = frontmostApplicationProvider(),
            isExternalApplication(frontmostApplication)
        {
            lastExternalApplication = frontmostApplication
        }

        guard lastExternalApplication?.isTerminated != true else {
            lastExternalApplication = nil
            return nil
        }
        return lastExternalApplication
    }

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        frontmostApplicationProvider: @escaping @MainActor () -> NSRunningApplication? = {
            NSWorkspace.shared.frontmostApplication
        },
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.notificationCenter = notificationCenter
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.currentProcessIdentifier = currentProcessIdentifier

        if let frontmostApplication = frontmostApplicationProvider(),
            frontmostApplication.processIdentifier != currentProcessIdentifier
        {
            lastExternalApplication = frontmostApplication
        }

        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }

            MainActor.assumeIsolated {
                self?.handleAppActivation(application)
            }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    var currentApplicationInfo: SourceApplicationInfo {
        let application = currentApplication
        return SourceApplicationInfo(
            name: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier,
            bundlePath: application?.bundleURL?.path
        )
    }

    private func handleAppActivation(_ application: NSRunningApplication) {
        guard isExternalApplication(application) else { return }

        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication) -> Bool {
        application.processIdentifier != currentProcessIdentifier && !application.isTerminated
    }
}
