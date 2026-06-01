import AppKit
import XCTest
@testable import Buffer

@MainActor
final class SettingsWindowCoordinatorTests: XCTestCase {
    func testShowWindowCreatesControllerOnceAndPresentsWindow() {
        let appActivation = RecordingAppActivationController()
        let window = TrackingSettingsWindow()
        let controller = RecordingSettingsWindowController(window: window)
        var factoryCallCount = 0
        let coordinator = SettingsWindowCoordinator(appActivationController: appActivation) { _ in
            factoryCallCount += 1
            return controller
        }

        coordinator.showWindow()
        coordinator.showWindow()

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(controller.showWindowCallCount, 1)
        XCTAssertEqual(window.centerCallCount, 2)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 2)
        XCTAssertEqual(appActivation.setDockIconVisibleCalls, [true, true])
        XCTAssertEqual(appActivation.activateAppCallCount, 2)
    }

    func testWindowCloseClearsControllerAndHidesDockIcon() {
        let appActivation = RecordingAppActivationController()
        let window = TrackingSettingsWindow()
        var createdControllers: [RecordingSettingsWindowController] = []
        let coordinator = SettingsWindowCoordinator(appActivationController: appActivation) { _ in
            let controller = RecordingSettingsWindowController(window: window)
            createdControllers.append(controller)
            return controller
        }

        coordinator.showWindow()
        coordinator.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        coordinator.showWindow()

        XCTAssertEqual(createdControllers.count, 2)
        XCTAssertEqual(appActivation.setDockIconVisibleCalls, [true, false, true])
    }
}

@MainActor
private final class RecordingAppActivationController: AppActivationControlling {
    private(set) var setDockIconVisibleCalls: [Bool] = []
    private(set) var activateAppCallCount = 0

    func setDockIconVisible(_ visible: Bool) {
        setDockIconVisibleCalls.append(visible)
    }

    func activateApp() {
        activateAppCallCount += 1
    }
}

@MainActor
private final class RecordingSettingsWindowController: SettingsWindowControlling {
    private let trackedWindow: TrackingSettingsWindow
    private(set) var showWindowCallCount = 0

    init(window: TrackingSettingsWindow) {
        trackedWindow = window
    }

    func showWindow(_ sender: Any?) {
        showWindowCallCount += 1
    }

    func windowReference() -> (any SettingsWindowType)? {
        trackedWindow
    }
}

@MainActor
private final class TrackingSettingsWindow: NSWindow {
    private(set) var centerCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    override func center() {
        centerCallCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }
}
