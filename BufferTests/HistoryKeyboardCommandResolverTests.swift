import AppKit
import XCTest

@testable import Buffer

final class HistoryKeyboardCommandResolverTests: XCTestCase {
    func testArrowUpWithCommandShiftResolvesToExtendToFirst() {
        let command = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 126,
                modifierFlags: [.command, .shift],
                isTextInputFocused: false,
                hasTextSelection: false
            )
        )

        XCTAssertEqual(command, .moveToFirst(extendSelection: true))
    }

    func testCommandCPreservesNativeCopyWhenTextIsSelected() {
        let command = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 8,
                modifierFlags: [.command],
                isTextInputFocused: true,
                hasTextSelection: true
            )
        )

        XCTAssertNil(command)
    }

    func testReturnPastesOnlyWithoutModifiers() {
        XCTAssertEqual(resolve(keyCode: 36), .commitSelection)
        XCTAssertNil(resolve(keyCode: 36, modifierFlags: .option))
        XCTAssertNil(resolve(keyCode: 36, modifierFlags: .command))
    }

    func testCommandCResolvesToCopySelection() {
        XCTAssertEqual(resolve(keyCode: 8, modifierFlags: .command), .copySelection)
        XCTAssertEqual(
            resolve(keyCode: 8, modifierFlags: .command, isTextInputFocused: true),
            .copySelection
        )
        XCTAssertNil(resolve(keyCode: 8, modifierFlags: [.command, .shift]))
    }

    func testCommandBResolvesToToggleBookmark() {
        XCTAssertEqual(resolve(keyCode: 11, modifierFlags: .command), .toggleBookmark)
        XCTAssertNil(resolve(keyCode: 11, modifierFlags: [.command, .shift]))
    }

    func testCommandASelectsAllOnlyWhenListHasKeyboardFocus() {
        let listCommand = resolve(keyCode: 0, modifierFlags: .command)
        let textCommand = resolve(
            keyCode: 0,
            modifierFlags: .command,
            isTextInputFocused: true
        )

        XCTAssertEqual(listCommand, .selectAll)
        XCTAssertNil(textCommand)
    }

    func testDeleteVariantsResolveForListSelection() {
        XCTAssertEqual(resolve(keyCode: 51), .deleteSelection)
        XCTAssertEqual(resolve(keyCode: 51, modifierFlags: .command), .deleteSelection)
        XCTAssertEqual(resolve(keyCode: 117), .deleteSelection)
    }

    func testDeleteDoesNotInterceptTextEditingOrUnsupportedModifiers() {
        XCTAssertNil(resolve(keyCode: 51, isTextInputFocused: true))
        XCTAssertNil(resolve(keyCode: 117, isTextInputFocused: true))
        XCTAssertEqual(
            resolve(keyCode: 51, modifierFlags: .command, isTextInputFocused: true),
            .deleteSelection
        )
        XCTAssertNil(resolve(keyCode: 51, modifierFlags: .option))
        XCTAssertNil(resolve(keyCode: 51, modifierFlags: .shift))
    }

    func testQuickPasteRequiresCommandOnly() {
        let validCommand = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 18,
                modifierFlags: [.command],
                isTextInputFocused: false,
                hasTextSelection: false
            )
        )
        let ignoredCommand = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 18,
                modifierFlags: [.command, .shift],
                isTextInputFocused: false,
                hasTextSelection: false
            )
        )

        XCTAssertEqual(validCommand, .quickPaste(0))
        XCTAssertNil(ignoredCommand)
    }

    func testFlagsChangedEmitsModifierCommand() {
        let command = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .flagsChanged,
                keyCode: 0,
                modifierFlags: [.command, .option],
                isTextInputFocused: false,
                hasTextSelection: false
            )
        )

        XCTAssertEqual(command, .modifiersChanged([.command, .option]))
    }

    private func resolve(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        isTextInputFocused: Bool = false,
        hasTextSelection: Bool = false
    ) -> HistoryKeyboardCommand? {
        HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                isTextInputFocused: isTextInputFocused,
                hasTextSelection: hasTextSelection
            )
        )
    }
}
