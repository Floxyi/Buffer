import XCTest
import AppKit
@testable import Buffer

@MainActor
final class HistoryKeyboardCommandHandlerTests: XCTestCase {
    func testDeleteSelectionPresentsConfirmationWhenEnabled() {
        let request = makeDeleteRequest(itemCount: 3)
        var presentedRequest: HistoryDeleteRequest?
        var deletedCount = 0

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: false,
            confirmDeleteWithKeyboardShortcut: true,
            actions: recorderActions(
                makeDeleteRequest: { request },
                deleteSelection: { _ in deletedCount += 1 },
                presentDeleteConfirmation: { presentedRequest = $0 }
            )
        )

        handler.handle(.deleteSelection)

        XCTAssertEqual(presentedRequest, request)
        XCTAssertEqual(presentedRequest?.selectionCount, 3)
        XCTAssertEqual(deletedCount, 0)
    }

    func testDeleteSelectionDeletesImmediatelyWhenConfirmationDisabled() {
        let request = makeDeleteRequest(itemCount: 1)
        var deletedRequest: HistoryDeleteRequest?
        var deletedCount = 0

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: false,
            confirmDeleteWithKeyboardShortcut: false,
            actions: recorderActions(
                makeDeleteRequest: { request },
                deleteSelection: {
                    deletedRequest = $0
                    deletedCount += 1
                }
            )
        )

        handler.handle(.deleteSelection)

        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(deletedRequest, request)
    }

    func testCommandsAreIgnoredWhileDeleteConfirmationIsPresenting() {
        var moveDownCallCount = 0
        var dismissCallCount = 0
        var quickPasteIndex: Int?

        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: true,
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
        selectAll: @escaping () -> Void = {},
        makeDeleteRequest: @escaping () -> HistoryDeleteRequest? = { nil },
        deleteSelection: @escaping (HistoryDeleteRequest) -> Void = { _ in },
        copySelection: @escaping () -> Void = {},
        togglePinned: @escaping () -> Void = {},
        saveImage: @escaping () -> Void = {},
        quickPaste: @escaping (Int) -> Void = { _ in },
        presentDeleteConfirmation: @escaping (HistoryDeleteRequest) -> Void = { _ in }
    ) -> HistoryKeyboardCommandHandler.Actions {
        .init(
            handleModifierFlagsChange: handleModifierFlagsChange,
            moveUp: moveUp,
            moveDown: moveDown,
            moveToFirst: moveToFirst,
            moveToLast: moveToLast,
            commitSelection: commitSelection,
            dismiss: dismiss,
            selectAll: selectAll,
            makeDeleteRequest: makeDeleteRequest,
            deleteSelection: deleteSelection,
            copySelection: copySelection,
            togglePinned: togglePinned,
            saveImage: saveImage,
            quickPaste: quickPaste,
            presentDeleteConfirmation: presentDeleteConfirmation
        )
    }

    private func makeDeleteRequest(itemCount: Int) -> HistoryDeleteRequest {
        HistoryDeleteRequest(
            items: (0..<itemCount).map { ClipboardItem.text("item-\($0)") },
            preferredSelectionID: nil
        )
    }
}
