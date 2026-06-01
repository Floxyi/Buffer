import XCTest
@testable import Buffer

@MainActor
final class ClipboardAssetStoreTests: XCTestCase {
    func testFullTextAndTextChunkReadStoredTextFile() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let filename = try XCTUnwrap(assetStore.saveText("abcdefghijklmnopqrstuvwxyz"))
        let item = ClipboardItem.largeText(preview: "abc", filename: filename)

        XCTAssertEqual(assetStore.fullText(for: item), "abcdefghijklmnopqrstuvwxyz")

        let chunk = try XCTUnwrap(assetStore.textChunk(for: item, charCount: 5))
        XCTAssertEqual(chunk.text, "abcde")
        XCTAssertEqual(chunk.totalBytes, 26)
        XCTAssertFalse(chunk.reachedEOF)
    }

    func testTextChunkUsesInlineFallbackForTruncatedText() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let item = ClipboardItem.truncatedText("hello world", originalSizeBytes: 42, sourceApp: nil)
        let chunk = try XCTUnwrap(assetStore.textChunk(for: item, charCount: 5))

        XCTAssertEqual(chunk.text, "hello")
        XCTAssertEqual(chunk.totalBytes, 42)
        XCTAssertFalse(chunk.reachedEOF)
    }

    func testCleanupOrphanedAssetsKeepsReferencedFilesOnly() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let keptText = try XCTUnwrap(assetStore.saveText("keep"))
        let orphanText = try XCTUnwrap(assetStore.saveText("orphan"))
        let keptImage = try XCTUnwrap(assetStore.saveImage(makePNGData()))
        let orphanImage = try XCTUnwrap(assetStore.saveImage(makePNGData(color: .systemRed)))

        let items = [
            ClipboardItem.largeText(preview: "keep", filename: keptText),
            ClipboardItem.image(filename: keptImage)
        ]

        assetStore.cleanupOrphanedAssets(referencedBy: items)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.textsDirectory.appendingPathComponent(keptText).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.textsDirectory.appendingPathComponent(orphanText).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.imagesDirectory.appendingPathComponent(keptImage).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.imagesDirectory.appendingPathComponent(orphanImage).path))
    }

    func testImageDimensionsAndItemSizeUseStoredImageData() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let filename = try XCTUnwrap(assetStore.saveImage(makePNGData(size: NSSize(width: 7, height: 5))))
        let item = ClipboardItem.image(filename: filename)

        XCTAssertEqual(assetStore.imageDimensions(for: item), "7x5")
        XCTAssertNotNil(assetStore.itemSize(for: item))
    }
}
