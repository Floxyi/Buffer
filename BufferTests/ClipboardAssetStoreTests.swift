import XCTest

@testable import Buffer

@MainActor
final class ClipboardAssetStoreTests: XCTestCase {
    func testSearchTextAssetFilenameRejectsTraversalAndUnexpectedNames() {
        let validID = UUID()
        XCTAssertNotNil(ClipboardAssetFilename(rawValue: "\(validID.uuidString).txt"))
        for invalid in [
            "../\(validID.uuidString).txt",
            "/tmp/\(validID.uuidString).txt",
            "folder/\(validID.uuidString).txt",
            "folder\\\(validID.uuidString).txt",
            "not-a-uuid.txt",
            "\(validID.uuidString).json",
        ] {
            XCTAssertNil(ClipboardAssetFilename(rawValue: invalid), invalid)
        }
    }

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

    func testSearchSnapshotUsesStableFingerprintAndReadOnlyAsset() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let filename = try XCTUnwrap(assetStore.saveText("immutable searchable body"))
        let item = ClipboardItem.largeText(preview: "immutable", filename: filename)

        let before = try assetStore.fingerprint(for: item)
        let snapshot = try assetStore.snapshot(for: item, checkCancellation: {})
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: paths.textsDirectory.appendingPathComponent(filename).path
            )[.posixPermissions] as? NSNumber
        )

        XCTAssertEqual(snapshot.text, "immutable searchable body")
        XCTAssertEqual(snapshot.fingerprint, before)
        XCTAssertEqual(permissions.intValue & 0o777, 0o400)
    }

    func testReplacingSameNamedAssetChangesFingerprint() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let filename = try XCTUnwrap(assetStore.saveText("first-content"))
        let item = ClipboardItem.largeText(preview: "first", filename: filename)
        let url = paths.textsDirectory.appendingPathComponent(filename)
        let original = try assetStore.fingerprint(for: item)

        try FileManager.default.removeItem(at: url)
        try Data("other-content".utf8).write(to: url, options: .atomic)
        let replacement = try assetStore.fingerprint(for: item)

        XCTAssertEqual(original.byteCount, replacement.byteCount)
        XCTAssertNotEqual(original, replacement)
        XCTAssertEqual(
            try assetStore.snapshot(for: item, checkCancellation: {}).text,
            "other-content"
        )
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
            ClipboardItem.image(filename: keptImage),
        ]

        assetStore.cleanupOrphanedAssets(referencedBy: items)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.textsDirectory.appendingPathComponent(keptText).path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.textsDirectory.appendingPathComponent(orphanText).path))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.imagesDirectory.appendingPathComponent(keptImage).path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.imagesDirectory.appendingPathComponent(orphanImage).path))
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

    func testItemAssetProviderLoadsFileBackedTextMetadataAsynchronously() async throws {
        let settings = makeHistoryTestSettings()
        let store = makeHistoryTestStore(settings: settings)
        let text = "file-backed clipboard content"
        let filename = try XCTUnwrap(store.saveText(text))
        let item = ClipboardItem.largeText(preview: "file-backed", filename: filename)
        let provider = ClipboardItemAssetProvider(store: store, settings: settings)

        let fullText = await provider.loadFullText(for: item)
        let chunk = await provider.loadTextChunk(for: item, charCount: 4)
        let itemSize = await provider.loadItemSize(for: item)

        XCTAssertEqual(fullText, text)
        XCTAssertEqual(
            chunk,
            ClipboardTextChunk(text: "file", totalBytes: text.utf8.count, reachedEOF: false)
        )
        XCTAssertEqual(itemSize, text.utf8.count)
    }
}
