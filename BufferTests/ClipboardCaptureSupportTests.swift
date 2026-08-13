import XCTest

@testable import Buffer

@MainActor
final class ClipboardCaptureSupportTests: XCTestCase {
    func testTrailingSpacesAndTabsAreRemovedPerLineWithoutChangingLineEndings() {
        let text = "  leading  \n\tindented\t \r\nmiddle  value \t\rfinal\t  "

        XCTAssertEqual(
            ClipboardTextNormalizer.normalize(
                text,
                mode: .trimTrailingSpacesAndTabs
            ),
            "  leading\n\tindented\r\nmiddle  value\rfinal"
        )
    }

    func testTrailingNormalizationPreservesUnicodeWhitespaceAndNewlines() {
        let nonBreakingSpace = "\u{00A0}"
        let text = "value\(nonBreakingSpace) \n\n\t\n"

        XCTAssertEqual(
            ClipboardTextNormalizer.normalize(
                text,
                mode: .trimTrailingSpacesAndTabs
            ),
            "value\(nonBreakingSpace)\n\n\n"
        )
    }

    func testNonTrimmingModesPreserveTextExactly() {
        let text = " \tvalue \t\r\n"

        XCTAssertEqual(ClipboardTextNormalizer.normalize(text, mode: .preserve), text)
        XCTAssertEqual(
            ClipboardTextNormalizer.normalize(text, mode: .showSpacesAndTabs),
            text
        )
    }

    func testPreparedCaptureHashesNormalizedContentAndRejectsEmptyResult() throws {
        let first = try XCTUnwrap(
            PreparedClipboardText.make(
                from: "value  \nnext\t",
                whitespaceMode: .trimTrailingSpacesAndTabs
            )
        )
        let second = try XCTUnwrap(
            PreparedClipboardText.make(
                from: "value\nnext",
                whitespaceMode: .trimTrailingSpacesAndTabs
            )
        )

        XCTAssertEqual(first.text, "value\nnext")
        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertNil(
            PreparedClipboardText.make(
                from: " \t  ",
                whitespaceMode: .trimTrailingSpacesAndTabs
            )
        )
    }

    func testInlineTextLimitBoundaryStaysInline() async {
        let text = String(repeating: "a", count: ClipboardCaptureSupport.inlineTextLimit)

        let item = await ClipboardCaptureSupport.classifyTextItem(
            text,
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Inline text should not be saved to disk")
            return nil
        }

        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.textContent, text)
        XCTAssertNil(item.textFilename)
        XCTAssertFalse(item.isTruncated)
    }

    func testLargeTextClassificationCreatesFileBackedItemWhenSaveSucceeds() async throws {
        let text = String(repeating: "a", count: ClipboardCaptureSupport.inlineTextLimit + 100)

        let item = await ClipboardCaptureSupport.classifyTextItem(
            text,
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            "payload.txt"
        }

        XCTAssertEqual(item.kind, .text)
        XCTAssertEqual(item.textFilename, "payload.txt")
        XCTAssertEqual(item.textContent, String(text.prefix(ClipboardCaptureSupport.previewLength)))
        XCTAssertFalse(item.isTruncated)
    }

    func testLargeTextClassificationFallsBackToTruncatedTextWhenSaveFails() async {
        let text = String(repeating: "b", count: ClipboardCaptureSupport.inlineTextLimit + 100)

        let item = await ClipboardCaptureSupport.classifyTextItem(
            text,
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            nil
        }

        XCTAssertEqual(item.kind, .text)
        XCTAssertTrue(item.isTruncated)
        XCTAssertNil(item.textFilename)
        XCTAssertEqual(item.originalSizeBytes, text.utf8.count)
    }

    func testIsImageFileRecognizesImageExtensions() {
        XCTAssertTrue(ClipboardCaptureSupport.isImageFile("/tmp/screenshot.png"))
        XCTAssertTrue(ClipboardCaptureSupport.isImageFile("/tmp/photo.jpeg"))
        XCTAssertFalse(ClipboardCaptureSupport.isImageFile("/tmp/readme.txt"))
        XCTAssertFalse(ClipboardCaptureSupport.isImageFile("/tmp/no-extension"))
    }

    func testProcessedImageFileReturnsPNGDataAndHash() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("image.png")
        try makePNGData().write(to: fileURL, options: .atomic)

        let processed = try XCTUnwrap(
            ClipboardCaptureSupport.processedImageFile(fileURL.path, skippingHash: Int.min)
        )

        XCTAssertFalse(processed.pngData.isEmpty)
        XCTAssertNil(ClipboardCaptureSupport.processedImageFile(fileURL.path, skippingHash: processed.hash))
    }

    func testProcessImageFileSavesImageAndInvokesCallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("image.png")
        try makePNGData().write(to: fileURL, options: .atomic)

        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
        let sourceApp = SourceApplicationInfo(
            name: "Preview",
            bundleIdentifier: "com.apple.Preview",
            bundlePath: "/Applications/Preview.app"
        )
        var receivedHash: Int?
        var receivedItem: ClipboardItem?

        ClipboardCaptureSupport.processImageFile(
            fileURL.path,
            sourceApp: sourceApp,
            store: store,
            lastContentHash: Int.min
        ) { hash, item in
            receivedHash = hash
            receivedItem = item
        }

        await eventually {
            receivedHash != nil && receivedItem?.kind == .image
        }

        XCTAssertEqual(receivedItem?.sourceApp, "Preview")
        XCTAssertNotNil(receivedItem?.imageFilename)
    }

    func testProcessImageFileSkipsCallbackWhenHashMatches() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("image.png")
        try makePNGData().write(to: fileURL, options: .atomic)

        let processed = try XCTUnwrap(
            ClipboardCaptureSupport.processedImageFile(fileURL.path, skippingHash: Int.min)
        )
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
        var callbackCount = 0

        ClipboardCaptureSupport.processImageFile(
            fileURL.path,
            sourceApp: SourceApplicationInfo(
                name: "Preview",
                bundleIdentifier: "com.apple.Preview",
                bundlePath: "/Applications/Preview.app"
            ),
            store: store,
            lastContentHash: processed.hash
        ) { _, _ in
            callbackCount += 1
        }

        await eventually {
            callbackCount == 0 && store.items.isEmpty
        }
    }

    func testImageDataPrefersPNGAndFallsBackToOriginalData() throws {
        let namedPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        namedPasteboard.clearContents()
        let pngData = makePNGData()
        namedPasteboard.setData(pngData, forType: .png)

        let extractedPNGData = try XCTUnwrap(ClipboardCaptureSupport.imageData(from: namedPasteboard))
        XCTAssertFalse(extractedPNGData.isEmpty)

        let fallbackPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        fallbackPasteboard.clearContents()
        let invalidTIFFData = Data([0x00, 0x01, 0x02])
        fallbackPasteboard.setData(invalidTIFFData, forType: .tiff)

        XCTAssertEqual(
            ClipboardCaptureSupport.imageData(from: fallbackPasteboard),
            invalidTIFFData
        )
    }
}
