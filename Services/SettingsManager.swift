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

enum HistoryLimit: Int, CaseIterable, Codable, Sendable {
    case essential = 100
    case deep = 500
    case unlimited = 1000

    var label: String {
        switch self {
        case .essential: return "Essential"
        case .deep: return "Deep"
        case .unlimited: return "Unlimited"
        }
    }

    var subtitle: String {
        switch self {
        case .essential: return "100 items"
        case .deep: return "500 items"
        case .unlimited: return "1,000 items"
        }
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

    private enum Key {
        static let hotkeyModifiers = "hotkeyModifiers"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let historyLimit = "historyLimit"
        static let excludedApps = "excludedApps"
        static let preferInitialSelectionFromFirstNonPinnedItem = "preferInitialSelectionFromFirstNonPinnedItem"
        static let keepSearchTextAfterPaste = "keepSearchTextAfterPaste"
        static let textDetailFontStyle = "textDetailFontStyle"
        static let textDetailFontSize = "textDetailFontSize"
        static let historyRetentionPeriod = "historyRetentionPeriod"
        static let menuBarIcon = "menuBarIcon"
    }

    private let defaults: UserDefaults
    private let launchAtLoginController: LaunchAtLoginControlling

    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published private(set) var launchAtLogin: Bool
    @Published var historyLimit: HistoryLimit
    @Published var preferInitialSelectionFromFirstNonPinnedItem: Bool
    @Published var keepSearchTextAfterPaste: Bool
    @Published var textDetailFontStyle: TextDetailFontStyle
    @Published var textDetailFontSize: TextDetailFontSize
    @Published var historyRetentionPeriod: HistoryRetentionPeriod
    @Published private(set) var excludedApps: [ExcludedApp]
    @Published private(set) var persistedHistoryLimit: HistoryLimit
    @Published var menuBarIcon: MenuBarIcon

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

        let rawLimit = defaults.integer(forKey: Key.historyLimit)
        let initialHistoryLimit = HistoryLimit(rawValue: rawLimit) ?? .essential
        self.historyLimit = initialHistoryLimit
        self.persistedHistoryLimit = initialHistoryLimit
        self.preferInitialSelectionFromFirstNonPinnedItem = defaults.bool(
            forKey: Key.preferInitialSelectionFromFirstNonPinnedItem
        )
        self.keepSearchTextAfterPaste = defaults.bool(forKey: Key.keepSearchTextAfterPaste)

        let rawTextDetailFontStyle =
            defaults.string(forKey: Key.textDetailFontStyle) ?? TextDetailFontStyle.monospaced.rawValue
        self.textDetailFontStyle = TextDetailFontStyle(rawValue: rawTextDetailFontStyle) ?? .monospaced

        let rawTextDetailFontSize = defaults.integer(forKey: Key.textDetailFontSize)
        self.textDetailFontSize = TextDetailFontSize(rawValue: rawTextDetailFontSize) ?? .medium
        
        let rawMenuBarIcon = defaults.string(forKey: Key.menuBarIcon) ?? MenuBarIcon.clipboard.rawValue
        self.menuBarIcon = MenuBarIcon(rawValue: rawMenuBarIcon) ?? .clipboard

        let rawHistoryRetentionPeriod =
            defaults.string(forKey: Key.historyRetentionPeriod) ?? HistoryRetentionPeriod.never.rawValue
        self.historyRetentionPeriod = HistoryRetentionPeriod(rawValue: rawHistoryRetentionPeriod) ?? .never

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

    func setHistoryLimit(_ limit: HistoryLimit) {
        historyLimit = limit
        persistedHistoryLimit = limit
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

    func setPreferInitialSelectionFromFirstNonPinnedItem(_ enabled: Bool) {
        preferInitialSelectionFromFirstNonPinnedItem = enabled
        persist()
    }

    func setKeepSearchTextAfterPaste(_ enabled: Bool) {
        keepSearchTextAfterPaste = enabled
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
        defaults.set(historyLimit.rawValue, forKey: Key.historyLimit)
        defaults.set(preferInitialSelectionFromFirstNonPinnedItem, forKey: Key.preferInitialSelectionFromFirstNonPinnedItem)
        defaults.set(keepSearchTextAfterPaste, forKey: Key.keepSearchTextAfterPaste)
        defaults.set(textDetailFontStyle.rawValue, forKey: Key.textDetailFontStyle)
        defaults.set(textDetailFontSize.rawValue, forKey: Key.textDetailFontSize)
        defaults.set(historyRetentionPeriod.rawValue, forKey: Key.historyRetentionPeriod)
        defaults.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon)

        do {
            let data = try JSONEncoder().encode(excludedApps)
            defaults.set(data, forKey: Key.excludedApps)
        } catch {
            BufferLogger.settings.error("Failed to encode excluded apps: \(String(describing: error), privacy: .public)")
        }
    }
}
