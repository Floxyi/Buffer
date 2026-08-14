import Foundation

struct SettingsLoadedState {
    var hotkeyModifiers: HotkeyModifiers
    var hotkeyKeyCode: UInt16
    var launchAtLogin: Bool
    var historyLimit: Int
    var keepSearchTextAfterPaste: Bool
    var keepSearchTextAfterClosing: Bool
    var confirmDeleteWithKeyboardShortcut: Bool
    var historyWindowOpenBehavior: HistoryWindowOpenBehavior
    var quickPasteEnabled: Bool
    var quickPasteNumberingStart: QuickPasteNumberingStart
    var quickPasteEntryCount: Int
    var textDetailFontStyle: TextDetailFontStyle
    var textDetailFontSize: TextDetailFontSize
    var clipboardWhitespaceMode: ClipboardWhitespaceMode
    var enableAutomaticOCR: Bool
    var historyRetentionPeriod: HistoryRetentionPeriod
    var menuBarIcon: MenuBarIcon
    var enableWebsitePreviews: Bool
    var excludedApps: [ExcludedApp]
    var persistedHistoryLimit: Int

    static func load(
        from store: any SettingsPersisting,
        launchAtLoginController: LaunchAtLoginControlling
    ) -> SettingsLoadedState {
        let historyLimit = SettingsMigration.loadHistoryLimit(from: store)
        let quickPaste = SettingsMigration.loadQuickPasteSettings(from: store)
        let textDetail = SettingsMigration.loadTextDetailSettings(from: store)
        let privacy = SettingsMigration.loadPrivacySettings(from: store)

        return SettingsLoadedState(
            hotkeyModifiers: SettingsMigration.loadHotkeyModifiers(from: store),
            hotkeyKeyCode: SettingsMigration.loadHotkeyKeyCode(from: store),
            launchAtLogin: launchAtLoginController.isEnabled(),
            historyLimit: historyLimit,
            keepSearchTextAfterPaste: SettingsMigration.loadKeepSearchTextAfterPaste(from: store),
            keepSearchTextAfterClosing: SettingsMigration.loadKeepSearchTextAfterClosing(from: store),
            confirmDeleteWithKeyboardShortcut: SettingsMigration.loadConfirmDeleteWithKeyboardShortcut(from: store),
            historyWindowOpenBehavior: SettingsMigration.loadHistoryWindowOpenBehavior(from: store),
            quickPasteEnabled: quickPaste.enabled,
            quickPasteNumberingStart: quickPaste.numberingStart,
            quickPasteEntryCount: quickPaste.entryCount,
            textDetailFontStyle: textDetail.style,
            textDetailFontSize: textDetail.size,
            clipboardWhitespaceMode: SettingsMigration.loadClipboardWhitespaceMode(from: store),
            enableAutomaticOCR: SettingsMigration.loadEnableAutomaticOCR(from: store),
            historyRetentionPeriod: privacy.historyRetentionPeriod,
            menuBarIcon: SettingsMigration.loadMenuBarIcon(from: store),
            enableWebsitePreviews: privacy.enableWebsitePreviews,
            excludedApps: SettingsMigration.loadExcludedApps(from: store),
            persistedHistoryLimit: historyLimit
        )
    }

    static let defaults = SettingsLoadedState(
        hotkeyModifiers: SettingsDefaults.defaultHotkeyModifiers,
        hotkeyKeyCode: SettingsDefaults.defaultHotkeyKeyCode,
        launchAtLogin: false,
        historyLimit: SettingsDefaults.defaultHistoryLimit,
        keepSearchTextAfterPaste: SettingsDefaults.defaultSearchBehavior.keepSearchTextAfterPaste,
        keepSearchTextAfterClosing: SettingsDefaults.defaultSearchBehavior.keepSearchTextAfterClosing,
        confirmDeleteWithKeyboardShortcut: SettingsDefaults.defaultSearchBehavior.confirmDeleteWithKeyboardShortcut,
        historyWindowOpenBehavior: SettingsDefaults.defaultHistoryWindowOpenBehavior,
        quickPasteEnabled: SettingsDefaults.defaultQuickPasteSettings.enabled,
        quickPasteNumberingStart: SettingsDefaults.defaultQuickPasteSettings.numberingStart,
        quickPasteEntryCount: SettingsDefaults.defaultQuickPasteSettings.entryCount,
        textDetailFontStyle: SettingsDefaults.defaultTextDetailSettings.style,
        textDetailFontSize: SettingsDefaults.defaultTextDetailSettings.size,
        clipboardWhitespaceMode: SettingsDefaults.defaultClipboardWhitespaceMode,
        enableAutomaticOCR: SettingsDefaults.defaultEnableAutomaticOCR,
        historyRetentionPeriod: SettingsDefaults.defaultPrivacySettings.historyRetentionPeriod,
        menuBarIcon: SettingsDefaults.defaultMenuBarIcon,
        enableWebsitePreviews: SettingsDefaults.defaultPrivacySettings.enableWebsitePreviews,
        excludedApps: [],
        persistedHistoryLimit: SettingsDefaults.defaultHistoryLimit
    )
}
