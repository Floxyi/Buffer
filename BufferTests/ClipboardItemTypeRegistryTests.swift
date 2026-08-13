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

    func testShowsSourceApplicationHidesStructuredVisualEntries() throws {
        let color = ClipboardItem.color(
            ClipboardColorValue(red: 1, green: 0, blue: 0, alpha: 1),
            originalText: "#ff0000"
        )
        let link = ClipboardItem.link(
            URL(string: "https://openai.com")!,
            originalText: "https://openai.com"
        )
        let text = ClipboardItem.text("hello")
        let email = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com"))
        )

        XCTAssertFalse(ClipboardItemPresentation.showsSourceApplication(for: color))
        XCTAssertFalse(ClipboardItemPresentation.showsSourceApplication(for: link))
        XCTAssertFalse(ClipboardItemPresentation.showsSourceApplication(for: email))
        XCTAssertTrue(ClipboardItemPresentation.showsSourceApplication(for: text))
    }

    func testEmailRegistryCapabilitiesAreIndependentFromWebsiteLinks() throws {
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com"))
        )

        XCTAssertTrue(ClipboardItemTypeRegistry.canComposeEmail(for: item))
        XCTAssertFalse(ClipboardItemTypeRegistry.canOpenLink(for: item))
        XCTAssertFalse(ClipboardItemTypeRegistry.supportsImageAssets(for: item))
        XCTAssertFalse(ClipboardItemTypeRegistry.supportsTextChunks(for: item))
    }

    func testEmailRegistrySearchPasteAndSizeUseOriginalText() async throws {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
        let originalText = "  person@example.com\n"
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse(originalText))
        )

        XCTAssertEqual(
            ClipboardSearchContentExtractor.searchableText(for: item) { nil },
            originalText
        )
        let pasteText = await store.pasteText(for: item)
        XCTAssertEqual(pasteText, originalText)
        XCTAssertEqual(store.itemSize(for: item), originalText.utf8.count)
    }

    func testEmailRowsDoNotResolveSourceApplicationOrWebsiteIcons() async throws {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let sourceApp = SourceApplicationInfo(
            name: "Mail",
            bundleIdentifier: "com.apple.mail",
            bundlePath: "/System/Applications/Mail.app"
        )
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com")),
            sourceApp: sourceApp
        )

        XCTAssertNil(
            ClipboardItemIconLoader.cachedLeadingIcon(
                for: item,
                settings: settings
            )
        )
        let loadedIcon = await ClipboardItemIconLoader.loadPreferredLeadingIcon(
            for: item,
            settings: settings
        )
        XCTAssertNil(loadedIcon)
    }

    func testEmailMailtoURLIsSafelyConstructed() throws {
        let payload = try XCTUnwrap(ClipboardEmailValue.parse("person+buffer@example.com"))

        XCTAssertEqual(payload.mailtoURL?.scheme, "mailto")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(payload.mailtoURL), resolvingAgainstBaseURL: false)?.path,
            "person+buffer@example.com"
        )
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
