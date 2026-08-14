import Foundation

enum SettingsMigration {
    static func loadHotkeyModifiers(from store: any SettingsPersisting) -> HotkeyModifiers {
        if let savedMods = store.array(for: .hotkeyModifiers) as? [String] {
            return HotkeyModifiers(from: savedMods)
        }

        return SettingsDefaults.defaultHotkeyModifiers
    }

    static func loadHotkeyKeyCode(from store: any SettingsPersisting) -> UInt16 {
        let savedKeyCode = store.integer(for: .hotkeyKeyCode)
        return savedKeyCode > 0 ? UInt16(savedKeyCode) : SettingsDefaults.defaultHotkeyKeyCode
    }

    static func loadHistoryLimit(from store: any SettingsPersisting) -> Int {
        let rawLimit = store.object(for: .historyLimit) as? Int ?? SettingsDefaults.defaultHistoryLimit
        return SettingsDefaults.normalizedHistoryLimit(rawLimit)
    }

    static func loadKeepSearchTextAfterPaste(from store: any SettingsPersisting) -> Bool {
        if store.object(for: .keepSearchTextAfterPaste) != nil {
            return store.bool(for: .keepSearchTextAfterPaste)
        }

        return SettingsDefaults.defaultSearchBehavior.keepSearchTextAfterPaste
    }

    static func loadKeepSearchTextAfterClosing(from store: any SettingsPersisting) -> Bool {
        if store.object(for: .keepSearchTextAfterClosing) != nil {
            return store.bool(for: .keepSearchTextAfterClosing)
        }

        return SettingsDefaults.defaultSearchBehavior.keepSearchTextAfterClosing
    }

    static func loadConfirmDeleteWithKeyboardShortcut(from store: any SettingsPersisting) -> Bool {
        if store.object(for: .confirmDeleteWithKeyboardShortcut) != nil {
            return store.bool(for: .confirmDeleteWithKeyboardShortcut)
        }

        return SettingsDefaults.defaultSearchBehavior.confirmDeleteWithKeyboardShortcut
    }

    static func loadHistoryWindowOpenBehavior(from store: any SettingsPersisting) -> HistoryWindowOpenBehavior {
        if store.object(for: .keepHistoryWindowSelectionOnReopen) != nil {
            return store.bool(for: .keepHistoryWindowSelectionOnReopen)
                ? .keepLastSelection
                : SettingsDefaults.defaultHistoryWindowOpenBehavior
        }

        let rawValue = store.string(for: .historyWindowOpenBehavior)
        return HistoryWindowOpenBehavior(
            rawValue: rawValue ?? SettingsDefaults.defaultHistoryWindowOpenBehavior.rawValue)
            ?? SettingsDefaults.defaultHistoryWindowOpenBehavior
    }

    static func loadQuickPasteSettings(from store: any SettingsPersisting) -> QuickPasteSettings {
        let defaults = SettingsDefaults.defaultQuickPasteSettings
        let enabled =
            store.object(for: .quickPasteEnabled) != nil
            ? store.bool(for: .quickPasteEnabled)
            : defaults.enabled
        let numberingStart =
            QuickPasteNumberingStart(
                rawValue: store.string(for: .quickPasteNumberingStart) ?? defaults.numberingStart.rawValue
            ) ?? defaults.numberingStart
        let entryCount = store.object(for: .quickPasteEntryCount) as? Int ?? defaults.entryCount

        return QuickPasteSettings(enabled: enabled, numberingStart: numberingStart, entryCount: entryCount)
    }

    static func loadTextDetailSettings(from store: any SettingsPersisting) -> TextDetailSettings {
        let defaults = SettingsDefaults.defaultTextDetailSettings
        let style =
            TextDetailFontStyle(
                rawValue: store.string(for: .textDetailFontStyle) ?? defaults.style.rawValue
            ) ?? defaults.style
        let size = TextDetailFontSize(rawValue: store.integer(for: .textDetailFontSize)) ?? defaults.size
        return TextDetailSettings(style: style, size: size)
    }

    static func loadClipboardWhitespaceMode(
        from store: any SettingsPersisting
    ) -> ClipboardWhitespaceMode {
        guard let rawValue = store.string(for: .clipboardWhitespaceMode) else {
            return SettingsDefaults.defaultClipboardWhitespaceMode
        }

        return ClipboardWhitespaceMode(rawValue: rawValue)
            ?? SettingsDefaults.defaultClipboardWhitespaceMode
    }

    static func loadEnableAutomaticOCR(from store: any SettingsPersisting) -> Bool {
        guard store.object(for: .enableAutomaticOCR) != nil else {
            return SettingsDefaults.defaultEnableAutomaticOCR
        }
        return store.bool(for: .enableAutomaticOCR)
    }

    static func loadPrivacySettings(from store: any SettingsPersisting) -> PrivacySettings {
        let defaults = SettingsDefaults.defaultPrivacySettings
        let historyRetentionPeriod =
            HistoryRetentionPeriod(
                rawValue: store.string(for: .historyRetentionPeriod) ?? defaults.historyRetentionPeriod.rawValue
            ) ?? defaults.historyRetentionPeriod
        let enableWebsitePreviews =
            store.object(for: .enableWebsitePreviews) != nil
            ? store.bool(for: .enableWebsitePreviews)
            : defaults.enableWebsitePreviews

        return PrivacySettings(
            historyRetentionPeriod: historyRetentionPeriod,
            enableWebsitePreviews: enableWebsitePreviews
        )
    }

    static func loadMenuBarIcon(from store: any SettingsPersisting) -> MenuBarIcon {
        MenuBarIcon(rawValue: store.string(for: .menuBarIcon) ?? SettingsDefaults.defaultMenuBarIcon.rawValue)
            ?? SettingsDefaults.defaultMenuBarIcon
    }

    static func loadExcludedApps(from store: any SettingsPersisting) -> [ExcludedApp] {
        guard let data = store.data(for: .excludedApps) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ExcludedApp].self, from: data)
        } catch {
            BufferLogger.settings.error(
                "Failed to decode excluded apps: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
