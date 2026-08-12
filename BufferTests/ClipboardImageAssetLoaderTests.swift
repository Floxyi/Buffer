import XCTest

@testable import Buffer

@MainActor
final class ClipboardImageAssetLoaderTests: XCTestCase {
    func testLoadImageDimensionsTextCachesAndCanBeClearedPerItem() async throws {
        ClipboardImageAssetLoader.clearCaches()

        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
        let filename = try XCTUnwrap(store.saveImage(makePNGData(size: NSSize(width: 7, height: 5))))
        let item = ClipboardItem.image(filename: filename)

        let first = await ClipboardImageAssetLoader.loadImageDimensionsText(for: item, store: store)
        ClipboardImageAssetLoader.removeCachedAssets(for: item.id)
        let second = await ClipboardImageAssetLoader.loadImageDimensionsText(for: item, store: store)

        XCTAssertEqual(first, "7x5")
        XCTAssertEqual(second, "7x5")
    }

    func testThumbnailCacheKeyRoundsPixelSize() {
        let item = ClipboardItem.text("hello")

        XCTAssertEqual(
            ClipboardImageAssetLoader.thumbnailCacheKey(for: item, pixelSize: 27.6),
            "\(item.id.uuidString)-28"
        )
    }

    func testPrewarmVisibleImagesCachesThumbnailAndDimensions() async throws {
        ClipboardImageAssetLoader.clearCaches()

        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
        let filename = try XCTUnwrap(store.saveImage(makePNGData(size: NSSize(width: 9, height: 6))))
        let item = ClipboardItem.image(filename: filename)

        await ClipboardImageAssetLoader.prewarmVisibleImages(
            for: [item],
            store: store,
            leadingVisualSize: 28
        )

        XCTAssertNotNil(
            ClipboardImageAssetLoader.cachedThumbnail(
                for: item,
                leadingVisualSize: 28
            )
        )
        XCTAssertEqual(
            ClipboardImageAssetLoader.cachedImageDimensionsText(for: item),
            "9x6"
        )
    }
}
