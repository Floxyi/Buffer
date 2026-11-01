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
        if let configuration = AppLaunchEnvironment.uiValidationConfiguration {
            let storagePaths: ClipboardStoragePaths
            do {
                storagePaths = try await Task.detached(priority: .userInitiated) {
                    try configuration.prepareStorage()
                }.value
            } catch {
                preconditionFailure("Failed to prepare isolated UI validation storage: \(error)")
            }
            return await makeForUIValidation(
                configuration,
                storagePaths: storagePaths
            )
        }

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

    private static func makeForUIValidation(
        _ configuration: BufferUIValidationConfiguration,
        storagePaths: ClipboardStoragePaths
    ) async -> AppContainer {
        let settingsManager = configuration.makeSettingsManager()
        let activeApplicationMonitor = ActiveApplicationMonitor()
        let clipboardStore = await ClipboardStore.makeForApplication(
            settingsManager: settingsManager,
            storagePaths: storagePaths
        )
        let ocrService = OCRService()
        let clipboardWatcher = ClipboardWatcher(
            store: clipboardStore,
            settingsManager: settingsManager,
            activeApplicationProvider: activeApplicationMonitor,
            ocrService: ocrService
        )

        return AppContainer(
            settingsManager: settingsManager,
            activeApplicationMonitor: activeApplicationMonitor,
            clipboardStore: clipboardStore,
            clipboardWatcher: clipboardWatcher,
            pasteController: PasteController(store: clipboardStore),
            hotkeyManager: HotkeyManager(settingsManager: settingsManager),
            ocrService: ocrService,
            historyWindowConfiguration: .ephemeral
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
