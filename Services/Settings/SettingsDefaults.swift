import Foundation

enum SettingsDefaults {
    static let defaultHotkeyModifiers = HotkeyModifiers(shift: true, command: true)
    static let defaultHotkeyKeyCode: UInt16 = 9

    static let historyLimitRange = 1...10_000
    static let quickPasteEntryCountRange = 1...5

    static let defaultHistoryLimit = 100
    static let defaultHistoryWindowOpenBehavior: HistoryWindowOpenBehavior = .selectFirstNonPinnedItem
    static let defaultMenuBarIcon: MenuBarIcon = .clipboard
    static let defaultClipboardWhitespaceMode: ClipboardWhitespaceMode = .preserve

    static let defaultSearchBehavior = SearchBehaviorSettings(
        keepSearchTextAfterPaste: false,
        keepSearchTextAfterClosing: false,
        confirmDeleteWithKeyboardShortcut: true
    )

    static let defaultQuickPasteSettings = QuickPasteSettings(
        enabled: true,
        numberingStart: .pinnedSection,
        entryCount: 5
    )

    static let defaultTextDetailSettings = TextDetailSettings(
        style: .monospaced,
        size: .medium
    )

    static let defaultPrivacySettings = PrivacySettings(
        historyRetentionPeriod: .never,
        enableWebsitePreviews: true
    )

    static func normalizedHistoryLimit(_ limit: Int) -> Int {
        limit.clamped(to: historyLimitRange)
    }

    static func normalizedQuickPasteEntryCount(_ count: Int) -> Int {
        count.clamped(to: quickPasteEntryCountRange)
    }
}
