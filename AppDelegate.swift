import Cocoa
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let settingsToolbarIdentifier = NSToolbar.Identifier("BufferSettingsToolbar")

    private let container = AppContainer()

    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var settingsWindowController: NSWindowController?
    private var cancellables: Set<AnyCancellable> = []

    var settingsManager: SettingsManager {
        container.settingsManager
    }

    var clipboardStore: ClipboardStore {
        container.clipboardStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)

        configureFirstLaunchBehavior()
        configureClipboardCapture()
        configureStatusBar()
        configureHotkeyHandling()
        openHistoryWindowOnStartup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.clipboardWatcher.stopWatching()
        container.hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHistoryWindow(openedViaHotkey: false)
        return false
    }

    private func configureFirstLaunchBehavior() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "hasLaunchedBefore") else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.container.settingsManager.toggleLaunchAtLogin(true)
            defaults.set(true, forKey: "hasLaunchedBefore")
        }
    }

    private func configureClipboardCapture() {
        container.clipboardWatcher.startWatching()
    }

    private func configureStatusBar() {
        statusBarController = StatusBarController(
            store: container.clipboardStore,
            watcher: container.clipboardWatcher,
            settingsManager: container.settingsManager,
            onShowHistory: { [weak self] in
                self?.showHistoryWindow(openedViaHotkey: false)
            },
            onShowSettings: { [weak self] in
                self?.showSettingsWindow()
            }
        )
    }

    private func configureHotkeyHandling() {
        container.hotkeyManager.register { [weak self] in
            self?.toggleHistoryWindow(openedViaHotkey: true)
        }

        container.settingsManager.hotkeyPublisher
            .dropFirst()
            .sink { [weak self] _ in
                self?.container.hotkeyManager.reregister()
            }
            .store(in: &cancellables)
    }

    private func openHistoryWindowOnStartup() {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.showHistoryWindow(openedViaHotkey: false)
        }
    }

    private func toggleHistoryWindow(openedViaHotkey: Bool) {
        let historyWindowController = historyWindowController ?? makeHistoryWindowController()
        if let window = historyWindowController.window, window.isVisible {
            historyWindowController.close()
        } else {
            showHistoryWindow(openedViaHotkey: openedViaHotkey)
        }
    }

    private func showHistoryWindow(
        focusSearch: Bool = true,
        activateApp: Bool = true,
        openedViaHotkey: Bool
    ) {
        let historyWindowController = historyWindowController ?? makeHistoryWindowController()
        historyWindowController.showWindow(
            nil,
            focusSearch: focusSearch,
            activateApp: activateApp,
            suppressQuickPasteUntilModifiersReleased: openedViaHotkey
        )
    }

    private func makeHistoryWindowController() -> HistoryWindowController {
        let controller = HistoryWindowController(
            store: container.clipboardStore,
            settingsManager: container.settingsManager,
            activeApplicationProvider: container.activeApplicationMonitor,
            pasteController: container.pasteController,
            ocrService: container.ocrService,
            ignoreNextCapturedChange: { [weak watcher = container.clipboardWatcher] in
                watcher?.ignoreNextCapturedChange()
            }
        )
        historyWindowController = controller
        return controller
    }

    func showSettingsWindow() {
        if let controller = settingsWindowController, let window = controller.window {
            presentSettingsWindow(window)
            return
        }

        var settingsWindow: NSWindow?
        let hostingController = NSHostingController(
            rootView: SettingsView(settings: settingsManager, store: clipboardStore) { title in
                settingsWindow?.title = title
            }
        )

        let window = NSWindow(contentViewController: hostingController)
        settingsWindow = window

        let toolbar = NSToolbar(identifier: Self.settingsToolbarIdentifier)
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false

        window.title = "General"
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
        window.delegate = self

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        presentSettingsWindow(window)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              settingsWindowController?.window === window else {
            return
        }

        settingsWindowController = nil
        setDockIconVisible(false)
    }

    private func presentSettingsWindow(_ window: NSWindow) {
        setDockIconVisible(true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setDockIconVisible(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }
}
