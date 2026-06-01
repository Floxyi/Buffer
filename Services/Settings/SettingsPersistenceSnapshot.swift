import Foundation

struct SettingsPersistenceSnapshot {
    let hotkeyModifiers: [String]
    let hotkeyKeyCode: Int
    let historyLimit: Int
    let keepSearchTextAfterPaste: Bool
    let keepSearchTextAfterClosing: Bool
    let confirmDeleteWithKeyboardShortcut: Bool
    let historyWindowOpenBehavior: String
    let quickPasteEnabled: Bool
    let quickPasteNumberingStart: String
    let quickPasteEntryCount: Int
    let textDetailFontStyle: String
    let textDetailFontSize: Int
    let historyRetentionPeriod: String
    let menuBarIcon: String
    let enableWebsitePreviews: Bool
    let excludedApps: [ExcludedApp]

    @MainActor
    init(settings: SettingsManager) {
        hotkeyModifiers = settings.hotkeyModifiers.toArray()
        hotkeyKeyCode = Int(settings.hotkeyKeyCode)
        historyLimit = settings.historyLimit
        keepSearchTextAfterPaste = settings.keepSearchTextAfterPaste
        keepSearchTextAfterClosing = settings.keepSearchTextAfterClosing
        confirmDeleteWithKeyboardShortcut = settings.confirmDeleteWithKeyboardShortcut
        historyWindowOpenBehavior = settings.historyWindowOpenBehavior.rawValue
        quickPasteEnabled = settings.quickPasteEnabled
        quickPasteNumberingStart = settings.quickPasteNumberingStart.rawValue
        quickPasteEntryCount = settings.quickPasteEntryCount
        textDetailFontStyle = settings.textDetailFontStyle.rawValue
        textDetailFontSize = settings.textDetailFontSize.rawValue
        historyRetentionPeriod = settings.historyRetentionPeriod.rawValue
        menuBarIcon = settings.menuBarIcon.rawValue
        enableWebsitePreviews = settings.enableWebsitePreviews
        excludedApps = settings.excludedApps
    }

    func persist(to store: any SettingsPersisting) {
        store.set(hotkeyModifiers, for: .hotkeyModifiers)
        store.set(hotkeyKeyCode, for: .hotkeyKeyCode)
        store.set(historyLimit, for: .historyLimit)
        store.set(keepSearchTextAfterPaste, for: .keepSearchTextAfterPaste)
        store.set(keepSearchTextAfterClosing, for: .keepSearchTextAfterClosing)
        store.set(confirmDeleteWithKeyboardShortcut, for: .confirmDeleteWithKeyboardShortcut)
        store.removeObject(for: .keepHistoryWindowSelectionOnReopen)
        store.set(historyWindowOpenBehavior, for: .historyWindowOpenBehavior)
        store.set(quickPasteEnabled, for: .quickPasteEnabled)
        store.set(quickPasteNumberingStart, for: .quickPasteNumberingStart)
        store.set(quickPasteEntryCount, for: .quickPasteEntryCount)
        store.set(textDetailFontStyle, for: .textDetailFontStyle)
        store.set(textDetailFontSize, for: .textDetailFontSize)
        store.set(historyRetentionPeriod, for: .historyRetentionPeriod)
        store.set(menuBarIcon, for: .menuBarIcon)
        store.set(enableWebsitePreviews, for: .enableWebsitePreviews)

        do {
            let data = try JSONEncoder().encode(excludedApps)
            store.set(data, for: .excludedApps)
        } catch {
            BufferLogger.settings.error("Failed to encode excluded apps: \(String(describing: error), privacy: .public)")
        }
    }
}
