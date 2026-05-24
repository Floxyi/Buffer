import Combine
import Foundation
import ServiceManagement

enum MenuBarIcon: String, CaseIterable, Codable, Sendable {
    case clipboard
    case clipboardDocument
    case stack
    case tray
    case bolt

    var label: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .clipboardDocument: return "Clipboard Document"
        case .stack: return "Stack"
        case .tray: return "Tray"
        case .bolt: return "Bolt"
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
        case .regular: return "Regular"
        case .monospaced: return "Monospaced"
        }
    }
}

enum TextDetailFontSize: Int, CaseIterable, Codable, Sendable {
    case small = 10
    case medium = 12
    case large = 14

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

enum HistoryRetentionPeriod: String, CaseIterable, Codable, Sendable {
    case never
    case twelveHours
    case twentyFourHours
    case oneWeek

    var label: String {
        switch self {
        case .never: return "Never"
        case .twelveHours: return "Older than 12 hours"
        case .twentyFourHours: return "Older than 24 hours"
        case .oneWeek: return "Older than 1 week"
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
        case .keepLastSelection: return "Keep last selection"
        case .selectFirstNonPinnedItem: return "Select first non-pinned item"
        case .selectAnyFirstItem: return "Select any first item"
        }
    }
}

enum QuickPasteNumberingStart: String, CaseIterable, Codable, Sendable {
    case pinnedSection
    case normalEntries

    var label: String {
        switch self {
        case .pinnedSection: return "Pinned section"
        case .normalEntries: return "Normal entries"
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
        self.shift = array.contains("shift")
        self.command = array.contains("command")
        self.option = array.contains("option")
        self.control = array.contains("control")
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

protocol LaunchAtLoginControlling {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

struct MainAppLaunchAtLoginController: LaunchAtLoginControlling {
    func isEnabled() -> Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
final class SettingsManager: ObservableObject {
    static let defaultHotkeyModifiers = HotkeyModifiers(shift: true, command: true)
    static let defaultHotkeyKeyCode: UInt16 = 9

    static let historyLimitRange = 1...10_000
    static let defaultHistoryLimit = 100
    static let defaultKeepSearchTextAfterPaste = false
    static let defaultKeepSearchTextAfterClosing = false
    static let defaultHistoryWindowOpenBehavior: HistoryWindowOpenBehavior = .selectFirstNonPinnedItem
    static let quickPasteEntryCountRange = 1...5
    static let defaultQuickPasteEnabled = true
    static let defaultQuickPasteNumberingStart: QuickPasteNumberingStart = .pinnedSection
    static let defaultQuickPasteEntryCount = 5
    static let defaultTextDetailFontStyle: TextDetailFontStyle = .monospaced
    static let defaultTextDetailFontSize: TextDetailFontSize = .medium
    static let defaultHistoryRetentionPeriod: HistoryRetentionPeriod = .never
    static let defaultMenuBarIcon: MenuBarIcon = .clipboard
    static let defaultEnableWebsitePreviews = true

    private enum Key {
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let historyLimit = "historyLimit"
        static let excludedApps = "excludedApps"
        static let keepSearchTextAfterPaste = "keepSearchTextAfterPaste"
        static let keepSearchTextAfterClosing = "keepSearchTextAfterClosing"
        static let keepHistoryWindowSelectionOnReopen = "keepHistoryWindowSelectionOnReopen"
        static let historyWindowOpenBehavior = "historyWindowOpenBehavior"
        static let quickPasteEnabled = "quickPasteEnabled"
        static let quickPasteNumberingStart = "quickPasteNumberingStart"
        static let quickPasteEntryCount = "quickPasteEntryCount"
        static let textDetailFontStyle = "textDetailFontStyle"
        static let textDetailFontSize = "textDetailFontSize"
        static let historyRetentionPeriod = "historyRetentionPeriod"
        static let menuBarIcon = "menuBarIcon"
        static let enableWebsitePreviews = "enableWebsitePreviews"
    }

    private let defaults: UserDefaults
    private let launchAtLoginController: LaunchAtLoginControlling

    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published private(set) var launchAtLogin: Bool
    @Published var historyLimit: Int
    @Published var keepSearchTextAfterPaste: Bool
    @Published var keepSearchTextAfterClosing: Bool
    @Published var historyWindowOpenBehavior: HistoryWindowOpenBehavior
    @Published var quickPasteEnabled: Bool
    @Published var quickPasteNumberingStart: QuickPasteNumberingStart
    @Published var quickPasteEntryCount: Int
    @Published var textDetailFontStyle: TextDetailFontStyle
    @Published var textDetailFontSize: TextDetailFontSize
    @Published var historyRetentionPeriod: HistoryRetentionPeriod
    @Published var menuBarIcon: MenuBarIcon
    @Published var enableWebsitePreviews: Bool
    @Published private(set) var excludedApps: [ExcludedApp]
    @Published private(set) var persistedHistoryLimit: Int

    var hotkeyPublisher: AnyPublisher<(UInt16, HotkeyModifiers), Never> {
        Publishers.CombineLatest($hotkeyKeyCode.removeDuplicates(), $hotkeyModifiers.removeDuplicates())
            .eraseToAnyPublisher()
    }

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginController: LaunchAtLoginControlling = MainAppLaunchAtLoginController()
    ) {
        self.defaults = defaults
        self.launchAtLoginController = launchAtLoginController

        if let savedMods = defaults.array(forKey: Key.hotkeyModifiers) as? [String] {
            self.hotkeyModifiers = HotkeyModifiers(from: savedMods)
        } else {
            self.hotkeyModifiers = Self.defaultHotkeyModifiers
        }

        let savedKeyCode = defaults.integer(forKey: Key.hotkeyKeyCode)
        self.hotkeyKeyCode = savedKeyCode > 0 ? UInt16(savedKeyCode) : Self.defaultHotkeyKeyCode

        let rawLimit = defaults.object(forKey: Key.historyLimit) as? Int ?? Self.defaultHistoryLimit
        let initialHistoryLimit = Self.normalizedHistoryLimit(rawLimit)
        self.historyLimit = initialHistoryLimit
        self.persistedHistoryLimit = initialHistoryLimit

        self.keepSearchTextAfterPaste = defaults.bool(forKey: Key.keepSearchTextAfterPaste)
        if defaults.object(forKey: Key.keepSearchTextAfterClosing) != nil {
            self.keepSearchTextAfterClosing = defaults.bool(forKey: Key.keepSearchTextAfterClosing)
        } else {
            self.keepSearchTextAfterClosing = Self.defaultKeepSearchTextAfterClosing
        }

        self.historyWindowOpenBehavior = Self.initialHistoryWindowOpenBehavior(defaults: defaults)

        if defaults.object(forKey: Key.quickPasteEnabled) != nil {
            self.quickPasteEnabled = defaults.bool(forKey: Key.quickPasteEnabled)
        } else {
            self.quickPasteEnabled = Self.defaultQuickPasteEnabled
        }

        let rawQuickPasteNumberingStart =
            defaults.string(forKey: Key.quickPasteNumberingStart) ?? Self.defaultQuickPasteNumberingStart.rawValue
        self.quickPasteNumberingStart =
            QuickPasteNumberingStart(rawValue: rawQuickPasteNumberingStart) ?? Self.defaultQuickPasteNumberingStart

        let rawQuickPasteEntryCount =
            defaults.object(forKey: Key.quickPasteEntryCount) as? Int ?? Self.defaultQuickPasteEntryCount
        self.quickPasteEntryCount = Self.normalizedQuickPasteEntryCount(rawQuickPasteEntryCount)

        let rawTextDetailFontStyle =
            defaults.string(forKey: Key.textDetailFontStyle) ?? Self.defaultTextDetailFontStyle.rawValue
        self.textDetailFontStyle = TextDetailFontStyle(rawValue: rawTextDetailFontStyle) ?? Self.defaultTextDetailFontStyle

        let rawTextDetailFontSize = defaults.integer(forKey: Key.textDetailFontSize)
        self.textDetailFontSize = TextDetailFontSize(rawValue: rawTextDetailFontSize) ?? Self.defaultTextDetailFontSize

        let rawHistoryRetentionPeriod =
            defaults.string(forKey: Key.historyRetentionPeriod) ?? Self.defaultHistoryRetentionPeriod.rawValue
        self.historyRetentionPeriod =
            HistoryRetentionPeriod(rawValue: rawHistoryRetentionPeriod) ?? Self.defaultHistoryRetentionPeriod

        let rawMenuBarIcon = defaults.string(forKey: Key.menuBarIcon) ?? Self.defaultMenuBarIcon.rawValue
        self.menuBarIcon = MenuBarIcon(rawValue: rawMenuBarIcon) ?? Self.defaultMenuBarIcon

        if defaults.object(forKey: Key.enableWebsitePreviews) != nil {
            self.enableWebsitePreviews = defaults.bool(forKey: Key.enableWebsitePreviews)
        } else {
            self.enableWebsitePreviews = Self.defaultEnableWebsitePreviews
        }

        if let data = defaults.data(forKey: Key.excludedApps) {
            do {
                self.excludedApps = try JSONDecoder().decode([ExcludedApp].self, from: data)
            } catch {
                BufferLogger.settings.error("Failed to decode excluded apps: \(String(describing: error), privacy: .public)")
                self.excludedApps = []
            }
        } else {
            self.excludedApps = []
        }

        self.launchAtLogin = launchAtLoginController.isEnabled()
    }

    func setHotkey(keyCode: UInt16, modifiers: HotkeyModifiers) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        persist()
    }

    static func normalizedHistoryLimit(_ limit: Int) -> Int {
        limit.clamped(to: historyLimitRange)
    }

    static func normalizedQuickPasteEntryCount(_ count: Int) -> Int {
        count.clamped(to: quickPasteEntryCountRange)
    }

    static func initialHistoryWindowOpenBehavior(defaults: UserDefaults) -> HistoryWindowOpenBehavior {
        if defaults.object(forKey: Key.keepHistoryWindowSelectionOnReopen) != nil {
            return defaults.bool(forKey: Key.keepHistoryWindowSelectionOnReopen)
                ? .keepLastSelection
                : Self.defaultHistoryWindowOpenBehavior
        }

        let rawValue = defaults.string(forKey: Key.historyWindowOpenBehavior)
        return normalizedHistoryWindowOpenBehavior(
            HistoryWindowOpenBehavior(rawValue: rawValue ?? Self.defaultHistoryWindowOpenBehavior.rawValue)
                ?? Self.defaultHistoryWindowOpenBehavior
        )
    }

    static func normalizedHistoryWindowOpenBehavior(_ rawValue: String) -> HistoryWindowOpenBehavior {
        normalizedHistoryWindowOpenBehavior(
            HistoryWindowOpenBehavior(rawValue: rawValue) ?? Self.defaultHistoryWindowOpenBehavior
        )
    }

    static func normalizedHistoryWindowOpenBehavior(_ behavior: HistoryWindowOpenBehavior) -> HistoryWindowOpenBehavior {
        behavior
    }

    func setHistoryLimit(_ limit: Int) {
        let normalizedLimit = Self.normalizedHistoryLimit(limit)
        historyLimit = normalizedLimit
        persistedHistoryLimit = normalizedLimit
        persist()
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLogin = launchAtLoginController.isEnabled()
        } catch {
            BufferLogger.settings.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
            launchAtLogin = launchAtLoginController.isEnabled()
        }
    }

    func setKeepSearchTextAfterPaste(_ enabled: Bool) {
        keepSearchTextAfterPaste = enabled
        persist()
    }

    func setKeepSearchTextAfterClosing(_ enabled: Bool) {
        keepSearchTextAfterClosing = enabled
        persist()
    }

    func setHistoryWindowOpenBehavior(_ behavior: HistoryWindowOpenBehavior) {
        historyWindowOpenBehavior = Self.normalizedHistoryWindowOpenBehavior(behavior)
        persist()
    }

    func setQuickPasteEnabled(_ enabled: Bool) {
        quickPasteEnabled = enabled
        persist()
    }

    func setQuickPasteNumberingStart(_ start: QuickPasteNumberingStart) {
        quickPasteNumberingStart = start
        persist()
    }

    func setQuickPasteEntryCount(_ count: Int) {
        quickPasteEntryCount = Self.normalizedQuickPasteEntryCount(count)
        persist()
    }

    func setTextDetailFontStyle(_ style: TextDetailFontStyle) {
        textDetailFontStyle = style
        persist()
    }

    func setTextDetailFontSize(_ size: TextDetailFontSize) {
        textDetailFontSize = size
        persist()
    }

    func setHistoryRetentionPeriod(_ period: HistoryRetentionPeriod) {
        historyRetentionPeriod = period
        persist()
    }

    func setMenuBarIcon(_ icon: MenuBarIcon) {
        menuBarIcon = icon
        persist()
    }

    func setEnableWebsitePreviews(_ enabled: Bool) {
        enableWebsitePreviews = enabled
        persist()
    }

    func resetUserPreferencesToDefaults() {
        hotkeyModifiers = Self.defaultHotkeyModifiers
        hotkeyKeyCode = Self.defaultHotkeyKeyCode

        historyLimit = Self.defaultHistoryLimit
        persistedHistoryLimit = Self.defaultHistoryLimit

        keepSearchTextAfterPaste = Self.defaultKeepSearchTextAfterPaste
        keepSearchTextAfterClosing = Self.defaultKeepSearchTextAfterClosing
        historyWindowOpenBehavior = Self.defaultHistoryWindowOpenBehavior
        quickPasteEnabled = Self.defaultQuickPasteEnabled
        quickPasteNumberingStart = Self.defaultQuickPasteNumberingStart
        quickPasteEntryCount = Self.defaultQuickPasteEntryCount

        textDetailFontStyle = Self.defaultTextDetailFontStyle
        textDetailFontSize = Self.defaultTextDetailFontSize
        historyRetentionPeriod = Self.defaultHistoryRetentionPeriod

        menuBarIcon = Self.defaultMenuBarIcon
        enableWebsitePreviews = Self.defaultEnableWebsitePreviews

        persist()
    }

    func addExcludedApp(_ app: ExcludedApp) {
        guard !excludedApps.contains(where: { $0.id == app.id }) else { return }
        excludedApps.append(app)
        excludedApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    func removeExcludedApp(id: ExcludedApp.ID) {
        excludedApps.removeAll { $0.id == id }
        persist()
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        removeExcludedApp(id: app.id)
    }

    func restoreDefaultHotkey() {
        setHotkey(keyCode: Self.defaultHotkeyKeyCode, modifiers: Self.defaultHotkeyModifiers)
    }

    func shouldExcludeCapture(from application: SourceApplicationInfo) -> Bool {
        excludedApps.contains { $0.matches(application) }
    }

    private func persist() {
        defaults.set(hotkeyModifiers.toArray(), forKey: Key.hotkeyModifiers)
        defaults.set(Int(hotkeyKeyCode), forKey: Key.hotkeyKeyCode)
        defaults.set(historyLimit, forKey: Key.historyLimit)
        defaults.set(keepSearchTextAfterPaste, forKey: Key.keepSearchTextAfterPaste)
        defaults.set(keepSearchTextAfterClosing, forKey: Key.keepSearchTextAfterClosing)
        defaults.removeObject(forKey: Key.keepHistoryWindowSelectionOnReopen)
        defaults.set(historyWindowOpenBehavior.rawValue, forKey: Key.historyWindowOpenBehavior)
        defaults.set(quickPasteEnabled, forKey: Key.quickPasteEnabled)
        defaults.set(quickPasteNumberingStart.rawValue, forKey: Key.quickPasteNumberingStart)
        defaults.set(quickPasteEntryCount, forKey: Key.quickPasteEntryCount)
        defaults.set(textDetailFontStyle.rawValue, forKey: Key.textDetailFontStyle)
        defaults.set(textDetailFontSize.rawValue, forKey: Key.textDetailFontSize)
        defaults.set(historyRetentionPeriod.rawValue, forKey: Key.historyRetentionPeriod)
        defaults.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon)
        defaults.set(enableWebsitePreviews, forKey: Key.enableWebsitePreviews)

        do {
            let data = try JSONEncoder().encode(excludedApps)
            defaults.set(data, forKey: Key.excludedApps)
        } catch {
            BufferLogger.settings.error("Failed to encode excluded apps: \(String(describing: error), privacy: .public)")
        }
    }
}
