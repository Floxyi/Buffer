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
                isTextInputFocused: false
            )
        )

        XCTAssertEqual(command, .moveToFirst(extendSelection: true))
    }

    func testCommandCDoesNotInterceptWhenTextInputIsFocused() {
        let command = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 8,
                modifierFlags: [.command],
                isTextInputFocused: true
            )
        )

        XCTAssertNil(command)
    }

    func testQuickPasteRequiresCommandOnly() {
        let validCommand = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 18,
                modifierFlags: [.command],
                isTextInputFocused: false
            )
        )
        let ignoredCommand = HistoryKeyboardCommandResolver.resolve(
            HistoryKeyboardInput(
                eventType: .keyDown,
                keyCode: 18,
                modifierFlags: [.command, .shift],
                isTextInputFocused: false
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
                isTextInputFocused: false
            )
        )

        XCTAssertEqual(command, .modifiersChanged([.command, .option]))
    }
}
