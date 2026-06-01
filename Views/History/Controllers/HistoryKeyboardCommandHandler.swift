import AppKit
import Foundation

@MainActor
struct HistoryKeyboardCommandHandler {
    struct Actions {
        var handleModifierFlagsChange: (NSEvent.ModifierFlags) -> Void
        var moveUp: (_ extendSelection: Bool) -> Void
        var moveDown: (_ extendSelection: Bool) -> Void
        var moveToFirst: (_ extendSelection: Bool) -> Void
        var moveToLast: (_ extendSelection: Bool) -> Void
        var commitSelection: (_ copyOnly: Bool) -> Void
        var dismiss: () -> Void
        var deleteSelection: () -> Void
        var copySelection: () -> Void
        var togglePinned: () -> Void
        var saveImage: () -> Void
        var quickPaste: (_ index: Int) -> Void
        var presentDeleteConfirmation: (_ selectionCount: Int) -> Void
    }

    let isDeleteConfirmationPresenting: Bool
    let selectionCount: Int
    let confirmDeleteWithKeyboardShortcut: Bool
    let actions: Actions

    func handle(_ command: HistoryKeyboardCommand) {
        switch command {
        case .modifiersChanged(let flags):
            actions.handleModifierFlagsChange(flags)

        case .moveUp(let extendSelection):
            guard !isDeleteConfirmationPresenting else { return }
            actions.moveUp(extendSelection)

        case .moveDown(let extendSelection):
            guard !isDeleteConfirmationPresenting else { return }
            actions.moveDown(extendSelection)

        case .moveToFirst(let extendSelection):
            guard !isDeleteConfirmationPresenting else { return }
            actions.moveToFirst(extendSelection)

        case .moveToLast(let extendSelection):
            guard !isDeleteConfirmationPresenting else { return }
            actions.moveToLast(extendSelection)

        case .commitSelection(let copyOnly):
            guard !isDeleteConfirmationPresenting else { return }
            actions.commitSelection(copyOnly)

        case .dismiss:
            guard !isDeleteConfirmationPresenting else { return }
            actions.dismiss()

        case .deleteSelection:
            guard !isDeleteConfirmationPresenting else { return }
            handleDeleteShortcut()

        case .copySelection:
            guard !isDeleteConfirmationPresenting else { return }
            actions.copySelection()

        case .togglePinned:
            guard !isDeleteConfirmationPresenting else { return }
            actions.togglePinned()

        case .saveImage:
            guard !isDeleteConfirmationPresenting else { return }
            actions.saveImage()

        case .quickPaste(let index):
            guard !isDeleteConfirmationPresenting else { return }
            actions.quickPaste(index)
        }
    }

    private func handleDeleteShortcut() {
        guard selectionCount > 0 else { return }

        if confirmDeleteWithKeyboardShortcut {
            actions.presentDeleteConfirmation(selectionCount)
        } else {
            actions.deleteSelection()
        }
    }
}

