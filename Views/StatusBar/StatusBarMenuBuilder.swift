import AppKit
import Foundation

@MainActor
struct StatusBarMenuBuilder {
    func makeMenu(
        settings: SettingsManager,
        isPaused: Bool,
        target: AnyObject,
        pauseAction: Selector,
        clearHistoryAction: Selector,
        showSettingsAction: Selector,
        quitAction: Selector
    ) -> NSMenu {
        let menu = NSMenu()

        let shortcutDisplay = AppFormatting.shortcutDisplay(
            modifiers: settings.hotkeyModifiers,
            keyCode: settings.hotkeyKeyCode
        )
        let shortcutItem = NSMenuItem(
            title: String(localized: "Shortcut: \(shortcutDisplay)"),
            action: nil,
            keyEquivalent: ""
        )
        shortcutItem.isEnabled = false
        menu.addItem(shortcutItem)

        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: isPaused
                    ? String(localized: "Resume Capture")
                    : String(localized: "Pause Capture"),
                action: pauseAction,
                target: target
            ))
        menu.addItem(
            actionItem(
                title: String(localized: "Clear History"),
                action: clearHistoryAction,
                target: target
            ))

        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: String(localized: "Settings..."),
                action: showSettingsAction,
                keyEquivalent: ",",
                target: target
            ))

        menu.addItem(.separator())
        menu.addItem(
            actionItem(
                title: String(localized: "Quit Buffer"),
                action: quitAction,
                keyEquivalent: "q",
                target: target
            ))

        return menu
    }

    private func actionItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }
}
