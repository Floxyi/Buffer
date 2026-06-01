import Cocoa
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let container = AppContainer()

    private var statusBarController: StatusBarController?
    private var cancellables: Set<AnyCancellable> = []
    private lazy var appStartupService = AppStartupService(launchAtLoginUpdater: container.settingsManager)
    private lazy var historyWindowCoordinator = HistoryWindowCoordinator { [unowned self] in
        self.makeHistoryWindowController()
    }
    private lazy var settingsWindowCoordinator = SettingsWindowCoordinator { [unowned self] delegate in
        SettingsWindowCoordinator.makeDefaultController(
            settingsManager: self.settingsManager,
            clipboardStore: self.clipboardStore,
            delegate: delegate
        )
    }

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
        historyWindowCoordinator.present(.standard(for: .reopen))
        return false
    }

    func showSettingsWindow() {
        settingsWindowCoordinator.showWindow()
    }

    private func configureFirstLaunchBehavior() {
        Task { @MainActor in
            await self.appStartupService.performFirstLaunchBootstrapIfNeeded()
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
                self?.historyWindowCoordinator.present(.standard(for: .statusBar))
            },
            onShowSettings: { [weak self] in
                self?.settingsWindowCoordinator.showWindow()
            }
        )
    }

    private func configureHotkeyHandling() {
        container.hotkeyManager.register { [weak self] in
            self?.historyWindowCoordinator.toggle(trigger: .hotkey)
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
            self?.historyWindowCoordinator.present(.standard(for: .startup))
        }
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
        return controller
    }
}
