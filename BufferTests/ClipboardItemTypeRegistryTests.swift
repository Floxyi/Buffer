import XCTest
@testable import Buffer

@MainActor
final class ClipboardItemTypeRegistryTests: XCTestCase {
    func testPrimaryLabelTextCollapsesWhitespaceAndTruncates() {
        let rawText = "Line  one\n\nLine\t two    " + String(repeating: "x", count: 80)
        let item = ClipboardItem.text(rawText)

        let label = ClipboardItemPresentation.primaryLabelText(for: item)

        XCTAssertFalse(label.contains("\n"))
        XCTAssertFalse(label.contains("\t"))
        XCTAssertTrue(label.hasSuffix("…"))
        XCTAssertLessThanOrEqual(label.count, 51)
    }

    func testShowsSourceApplicationHidesColorAndLinkEntries() {
        let color = ClipboardItem.color(
            ClipboardColorValue(red: 1, green: 0, blue: 0, alpha: 1),
            originalText: "#ff0000"
        )
        let link = ClipboardItem.link(
            URL(string: "https://openai.com")!,
            originalText: "https://openai.com"
        )
        let text = ClipboardItem.text("hello")

        XCTAssertFalse(ClipboardItemPresentation.showsSourceApplication(for: color))
        XCTAssertFalse(ClipboardItemPresentation.showsSourceApplication(for: link))
        XCTAssertTrue(ClipboardItemPresentation.showsSourceApplication(for: text))
    }

    func testSourceAppDisplayNameFallsBackToBundlePathThenIdentifier() {
        let pathOnlyItem = ClipboardItem(
            sourceApp: nil,
            sourceAppBundleIdentifier: nil,
            sourceAppBundlePath: "/Applications/Notes.app",
            content: .text(TextItemContent(inlineText: "body"))
        )
        let identifierOnlyItem = ClipboardItem(
            sourceApp: nil,
            sourceAppBundleIdentifier: "com.example.App",
            sourceAppBundlePath: nil,
            content: .text(TextItemContent(inlineText: "body"))
        )

        XCTAssertEqual(pathOnlyItem.sourceAppDisplayName, "Notes")
        XCTAssertEqual(identifierOnlyItem.sourceAppDisplayName, "com.example.App")
    }

    func testUpdatingOCRTextLeavesNonImageItemsUnchanged() {
        let textItem = ClipboardItem.text("hello")
        let imageItem = ClipboardItem.image(filename: "image.png")

        XCTAssertEqual(textItem.updatingOCRText("ignored"), textItem)
        XCTAssertEqual(imageItem.updatingOCRText("detected").ocrText, "detected")
    }
}
