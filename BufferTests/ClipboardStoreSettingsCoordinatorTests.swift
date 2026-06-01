import XCTest
@testable import Buffer

@MainActor
final class ClipboardStoreSettingsCoordinatorTests: XCTestCase {
    func testBindForwardsHistoryLimitAndRetentionChanges() {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let coordinator = ClipboardStoreSettingsCoordinator()

        var observedLimits: [Int] = []
        var retentionChangeCount = 0

        coordinator.bind(
            settingsManager: settings,
            onHistoryLimitChange: { observedLimits.append($0) },
            onHistoryRetentionPeriodChange: { retentionChangeCount += 1 }
        )

        settings.setHistoryLimit(42)
        settings.setPrivacySettings(
            PrivacySettings(
                historyRetentionPeriod: .twelveHours,
                enableWebsitePreviews: settings.enableWebsitePreviews
            )
        )

        XCTAssertEqual(observedLimits.last, 42)
        XCTAssertEqual(retentionChangeCount, 1)
    }
}
