import Foundation

@MainActor
protocol LaunchAtLoginUpdating: AnyObject {
    func setLaunchAtLoginEnabled(_ enabled: Bool)
}

extension SettingsManager: LaunchAtLoginUpdating {}

@MainActor
struct AppStartupService {
    static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    private let defaults: UserDefaults
    private let launchAtLoginUpdater: any LaunchAtLoginUpdating
    private let firstLaunchDelayNanoseconds: UInt64
    private let sleep: @Sendable (UInt64) async -> Void

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginUpdater: any LaunchAtLoginUpdating,
        firstLaunchDelayNanoseconds: UInt64 = 1_000_000_000,
        sleep: @escaping @Sendable (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.defaults = defaults
        self.launchAtLoginUpdater = launchAtLoginUpdater
        self.firstLaunchDelayNanoseconds = firstLaunchDelayNanoseconds
        self.sleep = sleep
    }

    func performFirstLaunchBootstrapIfNeeded() async {
        guard !defaults.bool(forKey: Self.hasLaunchedBeforeKey) else { return }

        await sleep(firstLaunchDelayNanoseconds)
        launchAtLoginUpdater.setLaunchAtLoginEnabled(true)
        defaults.set(true, forKey: Self.hasLaunchedBeforeKey)
    }
}
