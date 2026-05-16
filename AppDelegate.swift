import Cocoa
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let container = AppContainer()

    private var statusBarController: StatusBarController?
    private var historyWindowController: HistoryWindowController?
    private var cancellables: Set<AnyCancellable> = []

    var settingsManager: SettingsManager {
        container.settingsManager
    }

    var clipboardStore: ClipboardStore {
        container.clipboardStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
            hotkeyManager: container.hotkeyManager,
            onShowHistory: { [weak self] in
                self?.showHistoryWindow(openedViaHotkey: false)
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
}
