import XCTest

@testable import Buffer

final class ClipboardItemPresentationTests: XCTestCase {
    func testPreviewTextTruncatesLongTextAtTwoHundredCharacters() {
        let item = ClipboardItem.text(String(repeating: "a", count: 220))

        let preview = ClipboardItemPresentation.previewText(for: item)

        XCTAssertEqual(preview.count, 201)
        XCTAssertTrue(preview.hasSuffix("…"))
    }

    func testPrimaryLabelCollapsesWhitespaceAndTruncatesAtFiftyCharacters() {
        let item = ClipboardItem.text("first\n\nsecond\t\tthird " + String(repeating: "x", count: 60))

        let label = ClipboardItemPresentation.primaryLabelText(for: item)

        XCTAssertFalse(label.contains("\n"))
        XCTAssertFalse(label.contains("\t"))
        XCTAssertEqual(label.count, 51)
        XCTAssertTrue(label.hasSuffix("…"))
    }

    func testDefinitionExposesExpectedActionsForLinkAndImage() {
        let link = ClipboardItem.link(
            URL(string: "https://openai.com")!,
            originalText: "https://openai.com"
        )
        let image = ClipboardItem.image(
            filename: "image.png"
        )

        XCTAssertEqual(
            ClipboardItemPresentation.definition(for: link).detailActions,
            [.openLink]
        )
        XCTAssertEqual(
            ClipboardItemPresentation.definition(for: image).detailActions,
            [.saveImage, .extractImageText]
        )
    }

    func testEmailPresentationUsesDedicatedTypeAndComposeAction() throws {
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com"))
        )
        let definition = ClipboardItemPresentation.definition(for: item)

        XCTAssertEqual(definition.displayName, "Email")
        XCTAssertEqual(definition.detailActions, [.composeEmail])
        XCTAssertEqual(ClipboardItemPresentation.primaryLabelText(for: item), "person@example.com")

        guard case .email = ClipboardItemPresentation.leadingVisualStyle(for: item) else {
            return XCTFail("Expected the dedicated email leading visual")
        }
    }
}
