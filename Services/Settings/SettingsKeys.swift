import Foundation

enum SettingsKey: String, CaseIterable, Sendable {
    case hotkeyModifiers
    case hotkeyKeyCode
    case historyLimit
    case excludedApps
    case keepSearchTextAfterPaste
    case keepSearchTextAfterClosing
    case confirmDeleteWithKeyboardShortcut
    case keepHistoryWindowSelectionOnReopen
    case historyWindowOpenBehavior
    case quickPasteEnabled
    case quickPasteNumberingStart
    case quickPasteEntryCount
    case textDetailFontStyle
    case textDetailFontSize
    case clipboardWhitespaceMode
    case enableAutomaticOCR
    case historyRetentionPeriod
    case menuBarIcon
    case enableWebsitePreviews
}
