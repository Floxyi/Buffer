import AppKit
import Foundation

@MainActor
final class HistoryDeleteConfirmationController: ObservableObject {
    @Published private(set) var isPresenting = false

    func presentDeleteConfirmation(
        selectionCount: Int,
        onConfirm: @escaping () -> Void
    ) {
        guard !isPresenting else { return }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        isPresenting = true

        let alert = makeAlert(selectionCount: selectionCount)
        let deleteButton = alert.buttons[0]
        let alertWindow = alert.window
        alertWindow.defaultButtonCell = deleteButton.cell as? NSButtonCell

        nonisolated(unsafe) var alertKeyMonitor: Any?
        alertKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.modalWindow === alertWindow || event.window === alertWindow else { return event }

            switch event.keyCode {
            case 36:
                self.finishSheet(attachedTo: window, alertWindow: alertWindow, response: .alertFirstButtonReturn)
                return nil
            case 53:
                self.finishSheet(attachedTo: window, alertWindow: alertWindow, response: .alertSecondButtonReturn)
                return nil
            default:
                return event
            }
        }

        alert.beginSheetModal(for: window) { response in
            if let alertKeyMonitor {
                NSEvent.removeMonitor(alertKeyMonitor)
            }

            self.isPresenting = false

            if response == .alertFirstButtonReturn {
                onConfirm()
            }
        }
    }

    private func makeAlert(selectionCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = selectionCount == 1 ? "Delete item?" : "Delete \(selectionCount) items?"
        alert.informativeText = selectionCount == 1
            ? "This item will be removed from your clipboard history."
            : "These items will be removed from your clipboard history."

        let deleteButton = alert.addButton(withTitle: "Delete")
        deleteButton.keyEquivalent = "\r"
        deleteButton.keyEquivalentModifierMask = []
        if #available(macOS 11.0, *) {
            deleteButton.hasDestructiveAction = true
        }

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []
        return alert
    }

    private func finishSheet(
        attachedTo window: NSWindow,
        alertWindow: NSWindow,
        response: NSApplication.ModalResponse
    ) {
        window.endSheet(alertWindow, returnCode: response)
        alertWindow.orderOut(nil)
    }
}
