import AppKit
import SwiftUI

@MainActor
protocol AppActivationControlling {
    func setDockIconVisible(_ visible: Bool)
    func activateApp()
}

@MainActor
struct MainAppActivationController: AppActivationControlling {
    func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
protocol SettingsWindowType: AnyObject {
    var delegate: NSWindowDelegate? { get set }
    func center()
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NSWindow: SettingsWindowType {}

@MainActor
protocol SettingsWindowControlling: AnyObject {
    func showWindow(_ sender: Any?)
    func windowReference() -> (any SettingsWindowType)?
}

extension NSWindowController: SettingsWindowControlling {
    func windowReference() -> (any SettingsWindowType)? {
        window
    }
}

@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private static let settingsToolbarIdentifier = NSToolbar.Identifier("BufferSettingsToolbar")

    private let appActivationController: any AppActivationControlling
    private let controllerFactory: @MainActor (NSWindowDelegate) -> any SettingsWindowControlling
    private var settingsWindowController: (any SettingsWindowControlling)?

    init(
        appActivationController: any AppActivationControlling = MainAppActivationController(),
        controllerFactory: @escaping @MainActor (NSWindowDelegate) -> any SettingsWindowControlling
    ) {
        self.appActivationController = appActivationController
        self.controllerFactory = controllerFactory
        super.init()
    }

    func showWindow() {
        if let controller = settingsWindowController,
            let window = controller.windowReference()
        {
            present(window)
            return
        }

        let controller = controllerFactory(self)
        settingsWindowController = controller
        controller.showWindow(nil)

        if let window = controller.windowReference() {
            present(window)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let existingWindow = settingsWindowController?.windowReference() as? NSWindow,
            existingWindow === window
        else {
            return
        }

        settingsWindowController = nil
        appActivationController.setDockIconVisible(false)
    }

    private func present(_ window: any SettingsWindowType) {
        appActivationController.setDockIconVisible(true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        appActivationController.activateApp()
    }

    static func makeDefaultController(
        settingsManager: SettingsManager,
        clipboardStore: ClipboardStore,
        delegate: NSWindowDelegate
    ) -> NSWindowController {
        var settingsWindow: NSWindow?
        let hostingController = NSHostingController(
            rootView: SettingsView(settings: settingsManager, store: clipboardStore) { title in
                settingsWindow?.title = title
            }
        )

        let window = NSWindow(contentViewController: hostingController)
        settingsWindow = window

        let toolbar = NSToolbar(identifier: settingsToolbarIdentifier)
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false

        window.title = String(localized: "General")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.animationBehavior = .documentWindow
        window.setContentSize(NSSize(width: 780, height: 560))
        window.isReleasedWhenClosed = false
        window.delegate = delegate

        return NSWindowController(window: window)
    }
}
