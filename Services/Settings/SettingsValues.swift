import Foundation

enum MenuBarIcon: String, CaseIterable, Codable, Sendable {
    case clipboard
    case clipboardDocument
    case stack
    case tray
    case bolt

    var label: String {
        switch self {
        case .clipboard: return String(localized: "Clipboard")
        case .clipboardDocument: return String(localized: "Clipboard Document")
        case .stack: return String(localized: "Stack")
        case .tray: return String(localized: "Tray")
        case .bolt: return String(localized: "Bolt")
        }
    }

    var symbolName: String {
        switch self {
        case .clipboard: return "clipboard.fill"
        case .clipboardDocument: return "doc.on.clipboard"
        case .stack: return "square.stack.3d.up.fill"
        case .tray: return "tray.fill"
        case .bolt: return "bolt.fill"
        }
    }
}

struct ExcludedApp: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundlePath: String

    init(name: String, bundleIdentifier: String?, bundlePath: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.id = bundleIdentifier ?? bundlePath
    }

    func matches(_ application: SourceApplicationInfo) -> Bool {
        if let bundleIdentifier, bundleIdentifier == application.bundleIdentifier {
            return true
        }

        return bundlePath == application.bundlePath
    }
}

enum TextDetailFontStyle: String, CaseIterable, Codable, Sendable {
    case regular
    case monospaced

    var label: String {
        switch self {
        case .regular: return String(localized: "Regular")
        case .monospaced: return String(localized: "Monospaced")
        }
    }
}

enum TextDetailFontSize: Int, CaseIterable, Codable, Sendable {
    case small = 10
    case medium = 12
    case large = 14

    var label: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}

enum ClipboardWhitespaceMode: String, Codable, Sendable {
    case preserve
    case showSpacesAndTabs
    case trimTrailingSpacesAndTabs

    var showsSpacesAndTabs: Bool {
        self == .showSpacesAndTabs
    }

    var trimsTrailingSpacesAndTabs: Bool {
        self == .trimTrailingSpacesAndTabs
    }
}

enum HistoryRetentionPeriod: String, CaseIterable, Codable, Sendable {
    case never
    case twelveHours
    case twentyFourHours
    case oneWeek

    var label: String {
        switch self {
        case .never: return String(localized: "Never")
        case .twelveHours: return String(localized: "Older than 12 hours")
        case .twentyFourHours: return String(localized: "Older than 24 hours")
        case .oneWeek: return String(localized: "Older than 1 week")
        }
    }

    var maxAge: TimeInterval? {
        switch self {
        case .never: return nil
        case .twelveHours: return 12 * 60 * 60
        case .twentyFourHours: return 24 * 60 * 60
        case .oneWeek: return 7 * 24 * 60 * 60
        }
    }
}

enum HistoryWindowOpenBehavior: String, CaseIterable, Codable, Sendable {
    case keepLastSelection
    case selectFirstNonPinnedItem
    case selectAnyFirstItem

    var label: String {
        switch self {
        case .keepLastSelection: return String(localized: "Keep last selection")
        case .selectFirstNonPinnedItem: return String(localized: "Select first non-pinned item")
        case .selectAnyFirstItem: return String(localized: "Select any first item")
        }
    }
}

enum QuickPasteNumberingStart: String, CaseIterable, Codable, Sendable {
    case pinnedSection
    case normalEntries

    var label: String {
        switch self {
        case .pinnedSection: return String(localized: "Pinned section")
        case .normalEntries: return String(localized: "Normal entries")
        }
    }
}

struct HotkeyModifiers: Codable, Equatable, Sendable {
    var shift: Bool
    var command: Bool
    var option: Bool
    var control: Bool

    init(shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.shift = shift
        self.command = command
        self.option = option
        self.control = control
    }

    init(from array: [String]) {
        shift = array.contains("shift")
        command = array.contains("command")
        option = array.contains("option")
        control = array.contains("control")
    }

    func toArray() -> [String] {
        var result: [String] = []
        if shift { result.append("shift") }
        if command { result.append("command") }
        if option { result.append("option") }
        if control { result.append("control") }
        return result
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        return parts.joined()
    }
}

struct SearchBehaviorSettings: Equatable, Sendable {
    var keepSearchTextAfterPaste: Bool
    var keepSearchTextAfterClosing: Bool
    var confirmDeleteWithKeyboardShortcut: Bool
}

struct QuickPasteSettings: Equatable, Sendable {
    var enabled: Bool
    var numberingStart: QuickPasteNumberingStart
    var entryCount: Int

    init(enabled: Bool, numberingStart: QuickPasteNumberingStart, entryCount: Int) {
        self.enabled = enabled
        self.numberingStart = numberingStart
        self.entryCount = SettingsDefaults.normalizedQuickPasteEntryCount(entryCount)
    }
}

struct TextDetailSettings: Equatable, Sendable {
    var style: TextDetailFontStyle
    var size: TextDetailFontSize
}

struct PrivacySettings: Equatable, Sendable {
    var historyRetentionPeriod: HistoryRetentionPeriod
    var enableWebsitePreviews: Bool
}
