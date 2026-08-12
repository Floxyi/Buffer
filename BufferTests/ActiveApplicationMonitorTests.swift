import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ActiveApplicationMonitorTests: XCTestCase {
    func testCurrentApplicationInfoIsEmptyBeforeAnyActivation() {
        let notificationCenter = NotificationCenter()
        let monitor = ActiveApplicationMonitor(
            notificationCenter: notificationCenter,
            frontmostApplicationProvider: { nil }
        )

        XCTAssertNil(monitor.currentApplication)
        XCTAssertNil(monitor.currentApplicationInfo.name)
        XCTAssertNil(monitor.currentApplicationInfo.bundleIdentifier)
        XCTAssertNil(monitor.currentApplicationInfo.bundlePath)
    }

    func testIgnoresActivationForCurrentProcess() {
        let notificationCenter = NotificationCenter()
        let monitor = ActiveApplicationMonitor(
            notificationCenter: notificationCenter,
            frontmostApplicationProvider: { nil }
        )

        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current]
        )

        XCTAssertNil(monitor.currentApplication)
    }

    func testCapturesExternalFrontmostApplicationAtInitialization() {
        let frontmostApplication = NSRunningApplication.current
        let monitor = ActiveApplicationMonitor(
            notificationCenter: NotificationCenter(),
            frontmostApplicationProvider: { frontmostApplication },
            currentProcessIdentifier: frontmostApplication.processIdentifier + 1
        )

        XCTAssertEqual(monitor.currentApplication?.processIdentifier, frontmostApplication.processIdentifier)
    }

    func testCurrentApplicationRefreshesFromFrontmostApplication() {
        let notificationCenter = NotificationCenter()
        var frontmostApplication: NSRunningApplication?
        let monitor = ActiveApplicationMonitor(
            notificationCenter: notificationCenter,
            frontmostApplicationProvider: { frontmostApplication },
            currentProcessIdentifier: NSRunningApplication.current.processIdentifier + 1
        )
        XCTAssertNil(monitor.currentApplication)

        frontmostApplication = NSRunningApplication.current

        XCTAssertEqual(monitor.currentApplication?.processIdentifier, frontmostApplication?.processIdentifier)
    }
}
