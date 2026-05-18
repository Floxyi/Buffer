import Cocoa
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private static let settingsToolbarIdentifier = NSToolbar.Identifier("BufferSettingsToolbar")

    private let store: ClipboardStore
    private let watcher: ClipboardWatcher
    private let settingsManager: SettingsManager
    private let onToggleHistory: () -> Void
    private var settingsWindowController: NSWindowController?
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    init(
        store: ClipboardStore,
        watcher: ClipboardWatcher,
        settingsManager: SettingsManager,
        onShowHistory: @escaping () -> Void
    ) {
        self.store = store
        self.watcher = watcher
        self.settingsManager = settingsManager
        self.onToggleHistory = onShowHistory
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
        let menu = NSMenu()
        let shortcutDisplay = AppFormatting.shortcutDisplay(
            modifiers: settingsManager.hotkeyModifiers,
            keyCode: settingsManager.hotkeyKeyCode
        )
        let shortcutItem = NSMenuItem(title: "Shortcut: \(shortcutDisplay)", action: nil, keyEquivalent: "")
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(.separator())

        let pauseTitle = watcher.isPaused ? "Resume Capture" : "Pause Capture"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Buffer", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showSettings() {
        if let controller = settingsWindowController, let window = controller.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        var settingsWindow: NSWindow?
        let hostingController = NSHostingController(
            rootView: SettingsView(settings: settingsManager, store: store) { title in
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

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently delete all clipboard items."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
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
