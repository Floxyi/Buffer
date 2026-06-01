import AppKit
import XCTest
@testable import Buffer

@MainActor
final class ActiveApplicationMonitorTests: XCTestCase {
    func testCurrentApplicationInfoIsEmptyBeforeAnyActivation() {
        let notificationCenter = NotificationCenter()
        let monitor = ActiveApplicationMonitor(notificationCenter: notificationCenter)

        XCTAssertNil(monitor.currentApplication)
        XCTAssertNil(monitor.currentApplicationInfo.name)
        XCTAssertNil(monitor.currentApplicationInfo.bundleIdentifier)
        XCTAssertNil(monitor.currentApplicationInfo.bundlePath)
    }

    func testIgnoresActivationForCurrentProcess() {
        let notificationCenter = NotificationCenter()
        let monitor = ActiveApplicationMonitor(notificationCenter: notificationCenter)

        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        XCTAssertNil(monitor.currentApplication)
    }
}
