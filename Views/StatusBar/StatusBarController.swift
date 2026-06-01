import Cocoa
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private let settingsManager: SettingsManager
    private let onToggleHistory: () -> Void
    private let onShowSettings: () -> Void
    private let statusItem: NSStatusItem
    private let menuBuilder = StatusBarMenuBuilder()
    private let clearHistoryConfirmationPresenter = StatusBarClearHistoryConfirmationPresenter()
    private var cancellables = Set<AnyCancellable>()

    init(
        store: ClipboardStore,
        watcher: ClipboardWatcher,
        settingsManager: SettingsManager,
        onShowHistory: @escaping () -> Void,
        onShowSettings: @escaping () -> Void
    ) {
        self.store = store
        self.watcher = watcher
        self.settingsManager = settingsManager
        self.onToggleHistory = onShowHistory
        self.onShowSettings = onShowSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        setupButton()
        observeSettings()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }

        updateIcon(paused: watcher.isPaused)

        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    
    private func observeSettings() {
        settingsManager.$menuBarIcon
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateIcon(paused: self.watcher.isPaused)
                }
            }
            .store(in: &cancellables)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggleHistory()
            return
        }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onToggleHistory()
        }
    }

    private func showContextMenu() {
        let menu = menuBuilder.makeMenu(
            settings: settingsManager,
            isPaused: watcher.isPaused,
            target: self,
            pauseAction: #selector(togglePause),
            clearHistoryAction: #selector(clearHistory),
            showSettingsAction: #selector(showSettings),
            quitAction: #selector(quit)
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showSettings() {
        onShowSettings()
    }

    @objc private func togglePause() {
        if watcher.isPaused {
            watcher.resume()
            updateIcon(paused: false)
        } else {
            watcher.pause()
            updateIcon(paused: true)
        }
    }

    @objc private func clearHistory() {
        if clearHistoryConfirmationPresenter.confirmClearHistory() {
            store.clear()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon(paused: Bool) {
        guard let button = statusItem.button else { return }

        let symbolName = paused ? "pause.circle.fill" : settingsManager.menuBarIcon.symbolName
        let accessibilityDescription = paused ? "Buffer Paused" : "Buffer"

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true

        button.image = image?.withSymbolConfiguration(config)
    }
}
