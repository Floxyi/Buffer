import Foundation

@MainActor
final class AppContainer {
    let settingsManager: SettingsManager
    let activeApplicationMonitor: ActiveApplicationMonitor
    let clipboardStore: ClipboardStore
    let clipboardWatcher: ClipboardWatcher
    let pasteController: PasteController
    let hotkeyManager: HotkeyManager
    let ocrService: OCRService
    let historyWindowConfiguration: HistoryWindowConfiguration

    static func make() async -> AppContainer {
        let settingsManager = SettingsManager()
        let activeApplicationMonitor = ActiveApplicationMonitor()
        let clipboardStore = await ClipboardStore.makeForApplication(settingsManager: settingsManager)
        let ocrService = OCRService()
        let clipboardWatcher = ClipboardWatcher(
            store: clipboardStore,
            settingsManager: settingsManager,
            activeApplicationProvider: activeApplicationMonitor,
            ocrService: ocrService
        )
        let pasteController = PasteController(store: clipboardStore)
        let hotkeyManager = HotkeyManager(settingsManager: settingsManager)

        return AppContainer(
            settingsManager: settingsManager,
            activeApplicationMonitor: activeApplicationMonitor,
            clipboardStore: clipboardStore,
            clipboardWatcher: clipboardWatcher,
            pasteController: pasteController,
            hotkeyManager: hotkeyManager,
            ocrService: ocrService,
            historyWindowConfiguration: .standard
        )
    }

    private init(
        settingsManager: SettingsManager,
        activeApplicationMonitor: ActiveApplicationMonitor,
        clipboardStore: ClipboardStore,
        clipboardWatcher: ClipboardWatcher,
        pasteController: PasteController,
        hotkeyManager: HotkeyManager,
        ocrService: OCRService,
        historyWindowConfiguration: HistoryWindowConfiguration
    ) {
        self.settingsManager = settingsManager
        self.activeApplicationMonitor = activeApplicationMonitor
        self.clipboardStore = clipboardStore
        self.clipboardWatcher = clipboardWatcher
        self.pasteController = pasteController
        self.hotkeyManager = hotkeyManager
        self.ocrService = ocrService
        self.historyWindowConfiguration = historyWindowConfiguration
    }
}
