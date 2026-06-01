import XCTest
@testable import Buffer

@MainActor
final class ClipboardCaptureSupportTests: XCTestCase {
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
}
