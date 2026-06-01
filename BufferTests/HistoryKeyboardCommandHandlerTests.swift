import XCTest
import AppKit
@testable import Buffer

@MainActor
final class HistoryKeyboardCommandHandlerTests: XCTestCase {
    func testDeleteSelectionPresentsConfirmationWhenEnabled() {
        var presentedSelectionCount: Int?
        var deletedCount = 0

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: false,
            selectionCount: 3,
            confirmDeleteWithKeyboardShortcut: true,
            actions: recorderActions(
                deleteSelection: { deletedCount += 1 },
                presentDeleteConfirmation: { presentedSelectionCount = $0 }
            )
        )

        handler.handle(.deleteSelection)

        XCTAssertEqual(presentedSelectionCount, 3)
        XCTAssertEqual(deletedCount, 0)
    }

    func testDeleteSelectionDeletesImmediatelyWhenConfirmationDisabled() {
        var deletedCount = 0

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: false,
            selectionCount: 1,
            confirmDeleteWithKeyboardShortcut: false,
            actions: recorderActions(
                deleteSelection: { deletedCount += 1 }
            )
        )

        handler.handle(.deleteSelection)

        XCTAssertEqual(deletedCount, 1)
    }

    func testCommandsAreIgnoredWhileDeleteConfirmationIsPresenting() {
        var moveDownCallCount = 0
        var dismissCallCount = 0
        var quickPasteIndex: Int?

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: true,
            selectionCount: 1,
            confirmDeleteWithKeyboardShortcut: false,
            actions: recorderActions(
                moveDown: { _ in moveDownCallCount += 1 },
                dismiss: { dismissCallCount += 1 },
                quickPaste: { quickPasteIndex = $0 }
            )
        )

        handler.handle(.moveDown(extendSelection: false))
        handler.handle(.dismiss)
        handler.handle(.quickPaste(2))

        XCTAssertEqual(moveDownCallCount, 0)
        XCTAssertEqual(dismissCallCount, 0)
        XCTAssertNil(quickPasteIndex)
    }

    func testModifierChangesBypassDeleteConfirmationGuard() {
        var receivedFlags: NSEvent.ModifierFlags?

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: true,
            selectionCount: 0,
            confirmDeleteWithKeyboardShortcut: false,
            actions: recorderActions(
                handleModifierFlagsChange: { receivedFlags = $0 }
            )
        )

        handler.handle(.modifiersChanged(.command))

        XCTAssertEqual(receivedFlags, .command)
    }

    private func recorderActions(
        handleModifierFlagsChange: @escaping (NSEvent.ModifierFlags) -> Void = { _ in },
        moveUp: @escaping (Bool) -> Void = { _ in },
        moveDown: @escaping (Bool) -> Void = { _ in },
        moveToFirst: @escaping (Bool) -> Void = { _ in },
        moveToLast: @escaping (Bool) -> Void = { _ in },
        commitSelection: @escaping (Bool) -> Void = { _ in },
        dismiss: @escaping () -> Void = {},
        deleteSelection: @escaping () -> Void = {},
        copySelection: @escaping () -> Void = {},
        togglePinned: @escaping () -> Void = {},
        saveImage: @escaping () -> Void = {},
        quickPaste: @escaping (Int) -> Void = { _ in },
        presentDeleteConfirmation: @escaping (Int) -> Void = { _ in }
    ) -> HistoryKeyboardCommandHandler.Actions {
        .init(
            handleModifierFlagsChange: handleModifierFlagsChange,
            moveUp: moveUp,
            moveDown: moveDown,
            moveToFirst: moveToFirst,
            moveToLast: moveToLast,
            commitSelection: commitSelection,
            dismiss: dismiss,
            deleteSelection: deleteSelection,
            copySelection: copySelection,
            togglePinned: togglePinned,
            saveImage: saveImage,
            quickPaste: quickPaste,
            presentDeleteConfirmation: presentDeleteConfirmation
        )
    }
}
