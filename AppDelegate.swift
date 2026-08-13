import Cocoa
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: AppContainer?
    private var startupTask: Task<Void, Never>?

    private var statusBarController: StatusBarController?
    private var cancellables: Set<AnyCancellable> = []
    private var appStartupService: AppStartupService? {
        container.map { AppStartupService(launchAtLoginUpdater: $0.settingsManager) }
    }
    private lazy var historyWindowCoordinator = HistoryWindowCoordinator { [unowned self] in
        self.makeHistoryWindowController()
    }
    private lazy var settingsWindowCoordinator = SettingsWindowCoordinator { [unowned self] delegate in
        guard let container = self.container else {
            preconditionFailure("Settings requested before application services finished loading")
        }
        return SettingsWindowCoordinator.makeDefaultController(
            settingsManager: container.settingsManager,
            clipboardStore: container.clipboardStore,
            delegate: delegate
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppLaunchEnvironment.isRunningUnitTests else { return }

        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)

        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let container = await AppContainer.make()
            guard !Task.isCancelled else { return }
            self.container = container
            self.finishLaunching()
        }
    }

    private func finishLaunching() {
        configureFirstLaunchBehavior()
        configureClipboardCapture()
        configureStatusBar()
        configureHotkeyHandling()
        openHistoryWindowOnStartup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        container?.clipboardWatcher.stopWatching()
        container?.hotkeyManager.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard container != nil else { return false }
        historyWindowCoordinator.present(.standard(for: .reopen))
        return false
    }

    func showSettingsWindow() {
        guard container != nil else { return }
        settingsWindowCoordinator.showWindow()
    }

    private func configureFirstLaunchBehavior() {
        Task { @MainActor in
            await self.appStartupService?.performFirstLaunchBootstrapIfNeeded()
        }
    }

    private func configureClipboardCapture() {
        container?.clipboardWatcher.startWatching()
    }

    private func configureStatusBar() {
        guard let container else { return }
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
        guard let container else { return }
        container.hotkeyManager.register { [weak self] in
            self?.historyWindowCoordinator.toggle(trigger: .hotkey)
        }

        container.settingsManager.hotkeyPublisher
            .dropFirst()
            .sink { [weak self] _ in
                self?.container?.hotkeyManager.reregister()
            }
            .store(in: &cancellables)
    }

    private func openHistoryWindowOnStartup() {
        guard let container else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            self.historyWindowCoordinator.present(.standard(for: .startup))

            Task { @MainActor in
                async let persistedWebsiteIcons: Void = ClipboardWebsiteIconCache.hydratePersistedIcons()
                async let applicationIcons: Void = ClipboardApplicationIconLoader.shared.prewarmIcons(
                    for: container.clipboardStore.items,
                    limit: 80
                )
                async let legacyCacheCleanup: Void =
                    ClipboardLegacyApplicationIconCacheCleaner.shared.removeLegacyCacheIfNeeded()
                _ = await (persistedWebsiteIcons, applicationIcons, legacyCacheCleanup)

                await ClipboardItemIconLoader.prewarmPreferredIcons(
                    for: container.clipboardStore.items,
                    settings: container.settingsManager,
                    limit: 80
                )
            }
        }
    }

    private func makeHistoryWindowController() -> HistoryWindowController {
        guard let container else {
            preconditionFailure("History window requested before application services finished loading")
        }
        let controller = HistoryWindowController(
            store: container.clipboardStore,
            settingsManager: container.settingsManager,
            activeApplicationProvider: container.activeApplicationMonitor,
            pasteController: container.pasteController,
            ocrService: container.ocrService,
            windowConfiguration: container.historyWindowConfiguration,
            suppressCapturedChange: { [weak watcher = container.clipboardWatcher] receipt in
                watcher?.suppressCapture(forChangeCount: receipt.changeCount)
            }
        )
        return controller
    }
}

private enum AppLaunchEnvironment {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
