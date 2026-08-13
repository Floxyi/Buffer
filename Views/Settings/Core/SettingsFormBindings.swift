import SwiftUI

struct SettingsFormBindings {
    let launchAtLogin: Binding<Bool>
    let menuBarIcon: Binding<MenuBarIcon>
    let historyWindowOpenBehavior: Binding<HistoryWindowOpenBehavior>
    let searchBehavior: SettingsSearchBehaviorBindings
    let quickPaste: SettingsQuickPasteBindings
    let textDetail: SettingsTextDetailBindings
    let whitespace: SettingsWhitespaceBindings
    let privacy: SettingsPrivacyBindings
}

struct SettingsSearchBehaviorBindings {
    let keepSearchTextAfterPaste: Binding<Bool>
    let keepSearchTextAfterClosing: Binding<Bool>
    let confirmDeleteWithKeyboardShortcut: Binding<Bool>
}

struct SettingsQuickPasteBindings {
    let enabled: Binding<Bool>
    let numberingStart: Binding<QuickPasteNumberingStart>
    let entryCount: Binding<Int>
}

struct SettingsTextDetailBindings {
    let fontSize: Binding<TextDetailFontSize>
    let fontStyle: Binding<TextDetailFontStyle>
}

struct SettingsWhitespaceBindings {
    let showSpacesAndTabs: Binding<Bool>
    let trimTrailingSpacesAndTabs: Binding<Bool>
}

struct SettingsPrivacyBindings {
    let historyRetentionPeriod: Binding<HistoryRetentionPeriod>
    let enableWebsitePreviews: Binding<Bool>
}

extension SettingsManager {
    var formBindings: SettingsFormBindings {
        SettingsFormBindings(
            launchAtLogin: directBinding(
                value: { $0.launchAtLogin },
                apply: { settings, enabled in settings.setLaunchAtLoginEnabled(enabled) }
            ),
            menuBarIcon: directBinding(
                value: { $0.menuBarIcon },
                apply: { settings, icon in settings.setMenuBarIcon(icon) }
            ),
            historyWindowOpenBehavior: directBinding(
                value: { $0.historyWindowOpenBehavior },
                apply: { settings, behavior in settings.setHistoryWindowOpenBehavior(behavior) }
            ),
            searchBehavior: SettingsSearchBehaviorBindings(
                keepSearchTextAfterPaste: searchBehaviorBinding(\.keepSearchTextAfterPaste),
                keepSearchTextAfterClosing: searchBehaviorBinding(\.keepSearchTextAfterClosing),
                confirmDeleteWithKeyboardShortcut: searchBehaviorBinding(\.confirmDeleteWithKeyboardShortcut)
            ),
            quickPaste: SettingsQuickPasteBindings(
                enabled: quickPasteBinding(\.enabled),
                numberingStart: quickPasteBinding(\.numberingStart),
                entryCount: quickPasteBinding(\.entryCount)
            ),
            textDetail: SettingsTextDetailBindings(
                fontSize: textDetailBinding(\.size),
                fontStyle: textDetailBinding(\.style)
            ),
            whitespace: SettingsWhitespaceBindings(
                showSpacesAndTabs: whitespaceModeBinding(for: .showSpacesAndTabs),
                trimTrailingSpacesAndTabs: whitespaceModeBinding(for: .trimTrailingSpacesAndTabs)
            ),
            privacy: SettingsPrivacyBindings(
                historyRetentionPeriod: privacyBinding(\.historyRetentionPeriod),
                enableWebsitePreviews: privacyBinding(\.enableWebsitePreviews)
            )
        )
    }

    private var currentSearchBehavior: SearchBehaviorSettings {
        SearchBehaviorSettings(
            keepSearchTextAfterPaste: keepSearchTextAfterPaste,
            keepSearchTextAfterClosing: keepSearchTextAfterClosing,
            confirmDeleteWithKeyboardShortcut: confirmDeleteWithKeyboardShortcut
        )
    }

    private var currentQuickPasteSettings: QuickPasteSettings {
        QuickPasteSettings(
            enabled: quickPasteEnabled,
            numberingStart: quickPasteNumberingStart,
            entryCount: quickPasteEntryCount
        )
    }

    private var currentTextDetailSettings: TextDetailSettings {
        TextDetailSettings(
            style: textDetailFontStyle,
            size: textDetailFontSize
        )
    }

    private var currentPrivacySettings: PrivacySettings {
        PrivacySettings(
            historyRetentionPeriod: historyRetentionPeriod,
            enableWebsitePreviews: enableWebsitePreviews
        )
    }

    private func directBinding<Value>(
        value: @escaping (SettingsManager) -> Value,
        apply: @escaping (SettingsManager, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { value(self) },
            set: { apply(self, $0) }
        )
    }

    private func searchBehaviorBinding<Value>(
        _ keyPath: WritableKeyPath<SearchBehaviorSettings, Value>
    ) -> Binding<Value> {
        groupedBinding(
            currentValue: { $0.currentSearchBehavior },
            update: { settings, value in settings.setSearchBehavior(value) },
            keyPath: keyPath
        )
    }

    private func quickPasteBinding<Value>(
        _ keyPath: WritableKeyPath<QuickPasteSettings, Value>
    ) -> Binding<Value> {
        groupedBinding(
            currentValue: { $0.currentQuickPasteSettings },
            update: { settings, value in settings.setQuickPasteSettings(value) },
            keyPath: keyPath
        )
    }

    private func textDetailBinding<Value>(
        _ keyPath: WritableKeyPath<TextDetailSettings, Value>
    ) -> Binding<Value> {
        groupedBinding(
            currentValue: { $0.currentTextDetailSettings },
            update: { settings, value in settings.setTextDetailSettings(value) },
            keyPath: keyPath
        )
    }

    private func privacyBinding<Value>(
        _ keyPath: WritableKeyPath<PrivacySettings, Value>
    ) -> Binding<Value> {
        groupedBinding(
            currentValue: { $0.currentPrivacySettings },
            update: { settings, value in settings.setPrivacySettings(value) },
            keyPath: keyPath
        )
    }

    private func whitespaceModeBinding(for activeMode: ClipboardWhitespaceMode) -> Binding<Bool> {
        Binding(
            get: { self.clipboardWhitespaceMode == activeMode },
            set: { isEnabled in
                self.setClipboardWhitespaceMode(isEnabled ? activeMode : .preserve)
            }
        )
    }

    private func groupedBinding<Group, Value>(
        currentValue: @escaping (SettingsManager) -> Group,
        update: @escaping (SettingsManager, Group) -> Void,
        keyPath: WritableKeyPath<Group, Value>
    ) -> Binding<Value> {
        Binding(
            get: { currentValue(self)[keyPath: keyPath] },
            set: { newValue in
                var group = currentValue(self)
                group[keyPath: keyPath] = newValue
                update(self, group)
            }
        )
    }
}
