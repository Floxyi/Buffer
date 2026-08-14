import Cocoa
import Combine
import SwiftUI

struct StatusBarIconPresentation: Equatable {
    let symbolName: String
    let accessibilityDescription: String
    let appearsDisabled: Bool

    init(menuBarIcon: MenuBarIcon, isPaused: Bool) {
        symbolName = menuBarIcon.symbolName
        accessibilityDescription = isPaused ? "Buffer Paused" : "Buffer"
        appearsDisabled = isPaused
    }
}

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
        observeState()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }

        updateIcon(menuBarIcon: settingsManager.menuBarIcon, paused: watcher.isPaused)

        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func observeState() {
        settingsManager.$menuBarIcon
            .removeDuplicates()
            .combineLatest(watcher.$isPaused.removeDuplicates())
            .sink { [weak self] menuBarIcon, isPaused in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateIcon(menuBarIcon: menuBarIcon, paused: isPaused)
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
        } else {
            watcher.pause()
        }
    }

    @objc private func clearHistory() {
        guard clearHistoryConfirmationPresenter.confirmClearHistory() else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await store.clear()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "Couldn’t Clear History")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateIcon(menuBarIcon: MenuBarIcon, paused: Bool) {
        guard let button = statusItem.button else { return }

        let presentation = StatusBarIconPresentation(
            menuBarIcon: menuBarIcon,
            isPaused: paused
        )

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: presentation.accessibilityDescription
        )
        image?.isTemplate = true

        button.image = image?.withSymbolConfiguration(config)
        button.appearsDisabled = presentation.appearsDisabled
    }
}
