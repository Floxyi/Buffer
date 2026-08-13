import AppKit
import Foundation

@MainActor
struct StatusBarClearHistoryConfirmationPresenter {
    func confirmClearHistory(
        runAlert: @MainActor () -> NSApplication.ModalResponse = StatusBarClearHistoryConfirmationPresenter
            .runDefaultAlert
    ) -> Bool {
        runAlert() == .alertFirstButtonReturn
    }

    @MainActor
    private static func runDefaultAlert() -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently delete all clipboard items."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }
}
