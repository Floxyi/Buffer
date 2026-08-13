import XCTest

@testable import Buffer

final class HistoryActionResolverTests: XCTestCase {
    func testResolveActionsForMultipleItemsReturnsOrganizationActionsAndDelete() {
        let resolver = HistoryActionResolver()
        let actions = resolver.resolveActions(
            for: [ClipboardItem.text("one"), ClipboardItem.text("two")],
            allowsJumpToHistory: true,
            isExtractingText: false
        )

        XCTAssertEqual(actions.map(\.action), [.copy, .toggleBookmark, .togglePin, .delete])
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

        XCTAssertEqual(
            actions.map(\.action),
            [.copy, .openLink, .jumpToHistory, .toggleBookmark, .togglePin, .delete]
        )
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

        XCTAssertEqual(
            actions.map(\.action),
            [.copy, .composeEmail, .jumpToHistory, .toggleBookmark, .togglePin, .delete]
        )
    }

    func testProtectedItemsDoNotOfferDelete() {
        let pinned = ClipboardItem(
            isPinned: true,
            content: .text(TextItemContent(inlineText: "pinned"))
        )
        let bookmarked = ClipboardItem(
            isBookmarked: true,
            content: .text(TextItemContent(inlineText: "bookmarked"))
        )

        let actions = HistoryActionResolver().resolveActions(
            for: [pinned, bookmarked],
            allowsJumpToHistory: false,
            isExtractingText: false
        )

        XCTAssertFalse(actions.map(\.action).contains(.delete))
    }
}
