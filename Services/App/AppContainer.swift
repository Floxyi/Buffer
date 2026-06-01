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

    init() {
        let settingsManager = SettingsManager()
        let activeApplicationMonitor = ActiveApplicationMonitor()
        let clipboardStore = ClipboardStore(settingsManager: settingsManager)
        let clipboardWatcher = ClipboardWatcher(
            store: clipboardStore,
            settingsManager: settingsManager,
            activeApplicationProvider: activeApplicationMonitor
        )
        let pasteController = PasteController(store: clipboardStore)
        let hotkeyManager = HotkeyManager(settingsManager: settingsManager)

        self.settingsManager = settingsManager
        self.activeApplicationMonitor = activeApplicationMonitor
        self.clipboardStore = clipboardStore
        self.clipboardWatcher = clipboardWatcher
        self.pasteController = pasteController
        self.hotkeyManager = hotkeyManager
        self.ocrService = OCRService()
    }
}
