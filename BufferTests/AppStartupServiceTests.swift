import XCTest
@testable import Buffer

@MainActor
final class AppStartupServiceTests: XCTestCase {
    func testFirstLaunchEnablesLaunchAtLoginAndMarksDefaults() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let updater = RecordingLaunchAtLoginUpdater()
        let sleepRecorder = RecordingSleep()
        let service = AppStartupService(
            defaults: defaults,
            launchAtLoginUpdater: updater,
            firstLaunchDelayNanoseconds: 42,
            sleep: { nanoseconds in
                sleepRecorder.record(nanoseconds)
            }
        )

        await service.performFirstLaunchBootstrapIfNeeded()

        XCTAssertEqual(updater.toggledValues, [true])
        XCTAssertEqual(sleepRecorder.recordedNanoseconds, [42])
        XCTAssertTrue(defaults.bool(forKey: AppStartupService.hasLaunchedBeforeKey))
    }

    func testSubsequentLaunchSkipsBootstrap() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: AppStartupService.hasLaunchedBeforeKey)

        let updater = RecordingLaunchAtLoginUpdater()
        let sleepRecorder = RecordingSleep()
        let service = AppStartupService(
            defaults: defaults,
            launchAtLoginUpdater: updater,
            sleep: { _ in
                sleepRecorder.record(0)
            }
        )

        await service.performFirstLaunchBootstrapIfNeeded()

        XCTAssertTrue(updater.toggledValues.isEmpty)
        XCTAssertTrue(sleepRecorder.recordedNanoseconds.isEmpty)
    }
}

@MainActor
private final class RecordingLaunchAtLoginUpdater: LaunchAtLoginUpdating {
    private(set) var toggledValues: [Bool] = []

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        toggledValues.append(enabled)
    }
}

private final class RecordingSleep: @unchecked Sendable {
    private(set) var recordedNanoseconds: [UInt64] = []

    func record(_ nanoseconds: UInt64) {
        recordedNanoseconds.append(nanoseconds)
    }
}
