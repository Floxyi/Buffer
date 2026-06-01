import Combine
import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let historyLimitRange = SettingsDefaults.historyLimitRange
    static let quickPasteEntryCountRange = SettingsDefaults.quickPasteEntryCountRange

    private let store: any SettingsPersisting
    private let launchAtLoginController: LaunchAtLoginControlling

    @Published var hotkeyModifiers: HotkeyModifiers
    @Published var hotkeyKeyCode: UInt16
    @Published private(set) var launchAtLogin: Bool
    @Published var historyLimit: Int
    @Published var keepSearchTextAfterPaste: Bool
    @Published var keepSearchTextAfterClosing: Bool
    @Published var confirmDeleteWithKeyboardShortcut: Bool
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

    convenience init(
        defaults: UserDefaults = .standard,
        launchAtLoginController: LaunchAtLoginControlling = MainAppLaunchAtLoginController()
    ) {
        self.init(
            store: UserDefaultsSettingsStore(defaults: defaults),
            launchAtLoginController: launchAtLoginController
        )
    }

    init(
        store: any SettingsPersisting,
        launchAtLoginController: LaunchAtLoginControlling = MainAppLaunchAtLoginController()
    ) {
        self.store = store
        self.launchAtLoginController = launchAtLoginController
        let loadedState = SettingsLoadedState.load(
            from: store,
            launchAtLoginController: launchAtLoginController
        )

        hotkeyModifiers = loadedState.hotkeyModifiers
        hotkeyKeyCode = loadedState.hotkeyKeyCode
        launchAtLogin = loadedState.launchAtLogin
        historyLimit = loadedState.historyLimit
        keepSearchTextAfterPaste = loadedState.keepSearchTextAfterPaste
        keepSearchTextAfterClosing = loadedState.keepSearchTextAfterClosing
        confirmDeleteWithKeyboardShortcut = loadedState.confirmDeleteWithKeyboardShortcut
        historyWindowOpenBehavior = loadedState.historyWindowOpenBehavior
        quickPasteEnabled = loadedState.quickPasteEnabled
        quickPasteNumberingStart = loadedState.quickPasteNumberingStart
        quickPasteEntryCount = loadedState.quickPasteEntryCount
        textDetailFontStyle = loadedState.textDetailFontStyle
        textDetailFontSize = loadedState.textDetailFontSize
        historyRetentionPeriod = loadedState.historyRetentionPeriod
        menuBarIcon = loadedState.menuBarIcon
        enableWebsitePreviews = loadedState.enableWebsitePreviews
        excludedApps = loadedState.excludedApps
        persistedHistoryLimit = loadedState.persistedHistoryLimit
    }

    static func normalizedHistoryLimit(_ limit: Int) -> Int {
        SettingsDefaults.normalizedHistoryLimit(limit)
    }

    static func normalizedQuickPasteEntryCount(_ count: Int) -> Int {
        SettingsDefaults.normalizedQuickPasteEntryCount(count)
    }

    func setHotkey(keyCode: UInt16, modifiers: HotkeyModifiers) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        persist()
    }

    func setHistoryLimit(_ limit: Int) {
        let normalizedLimit = SettingsDefaults.normalizedHistoryLimit(limit)
        historyLimit = normalizedLimit
        persistedHistoryLimit = normalizedLimit
        persist()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLogin = launchAtLoginController.isEnabled()
        } catch {
            BufferLogger.settings.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
            launchAtLogin = launchAtLoginController.isEnabled()
        }
    }

    func setHistoryWindowOpenBehavior(_ behavior: HistoryWindowOpenBehavior) {
        historyWindowOpenBehavior = behavior
        persist()
    }

    func setSearchBehavior(_ behavior: SearchBehaviorSettings) {
        keepSearchTextAfterPaste = behavior.keepSearchTextAfterPaste
        keepSearchTextAfterClosing = behavior.keepSearchTextAfterClosing
        confirmDeleteWithKeyboardShortcut = behavior.confirmDeleteWithKeyboardShortcut
        persist()
    }

    func setQuickPasteSettings(_ settings: QuickPasteSettings) {
        quickPasteEnabled = settings.enabled
        quickPasteNumberingStart = settings.numberingStart
        quickPasteEntryCount = settings.entryCount
        persist()
    }

    func setTextDetailSettings(_ settings: TextDetailSettings) {
        textDetailFontStyle = settings.style
        textDetailFontSize = settings.size
        persist()
    }

    func setPrivacySettings(_ settings: PrivacySettings) {
        historyRetentionPeriod = settings.historyRetentionPeriod
        enableWebsitePreviews = settings.enableWebsitePreviews
        persist()
    }

    func setMenuBarIcon(_ icon: MenuBarIcon) {
        menuBarIcon = icon
        persist()
    }

    func resetUserPreferencesToDefaults() {
        applyLoadedState(
            SettingsLoadedState.defaults,
            preserveLaunchAtLogin: true
        )

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
        setHotkey(
            keyCode: SettingsDefaults.defaultHotkeyKeyCode,
            modifiers: SettingsDefaults.defaultHotkeyModifiers
        )
    }

    func shouldExcludeCapture(from application: SourceApplicationInfo) -> Bool {
        excludedApps.contains { $0.matches(application) }
    }

    private func persist() {
        SettingsPersistenceSnapshot(settings: self).persist(to: store)
    }

    private func applyLoadedState(
        _ state: SettingsLoadedState,
        preserveLaunchAtLogin: Bool = false
    ) {
        hotkeyModifiers = state.hotkeyModifiers
        hotkeyKeyCode = state.hotkeyKeyCode

        if !preserveLaunchAtLogin {
            launchAtLogin = state.launchAtLogin
        }

        historyLimit = state.historyLimit
        persistedHistoryLimit = state.persistedHistoryLimit
        keepSearchTextAfterPaste = state.keepSearchTextAfterPaste
        keepSearchTextAfterClosing = state.keepSearchTextAfterClosing
        confirmDeleteWithKeyboardShortcut = state.confirmDeleteWithKeyboardShortcut
        historyWindowOpenBehavior = state.historyWindowOpenBehavior
        quickPasteEnabled = state.quickPasteEnabled
        quickPasteNumberingStart = state.quickPasteNumberingStart
        quickPasteEntryCount = state.quickPasteEntryCount
        textDetailFontStyle = state.textDetailFontStyle
        textDetailFontSize = state.textDetailFontSize
        historyRetentionPeriod = state.historyRetentionPeriod
        menuBarIcon = state.menuBarIcon
        enableWebsitePreviews = state.enableWebsitePreviews
        excludedApps = state.excludedApps
    }
}
