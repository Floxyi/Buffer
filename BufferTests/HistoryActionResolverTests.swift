import XCTest
@testable import Buffer

final class HistoryActionResolverTests: XCTestCase {
    func testResolveActionsForMultipleItemsReturnsCopyPinDelete() {
        let resolver = HistoryActionResolver()
        let actions = resolver.resolveActions(
            for: [ClipboardItem.text("one"), ClipboardItem.text("two")],
            allowsJumpToHistory: true,
            isExtractingText: false
        )

        XCTAssertEqual(actions.map(\.action), [.copy, .togglePin, .delete])
    }

    func testResolveActionsForLinkIncludesOpenAndJump() {
        let resolver = HistoryActionResolver()
        let item = ClipboardItem.link(
            URL(string: "https://openai.com")!,
            originalText: "https://openai.com"
        )

        let actions = resolver.resolveActions(
            for: [item],
            allowsJumpToHistory: true,
            isExtractingText: false
        )

        XCTAssertEqual(actions.map(\.action), [.copy, .openLink, .jumpToHistory, .togglePin, .delete])
    }

    func testResolveActionsForEmailIncludesComposeButNotOpenWebsite() throws {
        let resolver = HistoryActionResolver()
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com"))
        )

        let actions = resolver.resolveActions(
            for: [item],
            allowsJumpToHistory: true,
            isExtractingText: false
        )

        XCTAssertEqual(actions.map(\.action), [.copy, .composeEmail, .jumpToHistory, .togglePin, .delete])
    }
}
