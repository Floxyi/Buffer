import AppKit
import XCTest
@testable import Buffer

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testAddRespectsHistoryLimitWhileKeepingPinnedItems() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryLimit(2)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let pinned = ClipboardItem.text("pinned")
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        store.add(pinned)
        await eventually { store.items.count == 1 }
        store.togglePin(for: pinned)
        await eventually { store.items.first?.isPinned == true }

        store.add(first)
        store.add(second)

        await eventually {
            store.items.map(\.textContent) == ["second", "pinned"]
        }
    }

    func testTogglePinSetsAndClearsPinnedState() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("pin me")

        store.add(item)
        await eventually { store.items.count == 1 }

        store.togglePin(for: item)
        await eventually {
            store.items.first?.isPinned == true && store.items.first?.pinnedAt != nil
        }

        let pinnedItem = try! XCTUnwrap(store.items.first)
        store.togglePin(for: pinnedItem)
        await eventually {
            store.items.first?.isPinned == false && store.items.first?.pinnedAt == nil
        }
    }

    func testMoveToTopReordersExistingItems() async {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let first = ClipboardItem.text("one")
        let second = ClipboardItem.text("two")
        let third = ClipboardItem.text("three")

        store.add(first)
        store.add(second)
        store.add(third)

        await eventually {
            store.items.map(\.textContent) == ["three", "two", "one"]
        }

        store.moveToTop(first)

        await eventually(timeoutNanoseconds: 3_000_000_000) {
            store.items.map(\.textContent) == ["one", "three", "two"]
        }
    }

    func testSetOCRTextUpdatesImagePayload() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)

        store.add(item)
        await eventually { store.items.count == 1 }

        store.setOCRText("detected text", for: item)

        await eventually {
            store.items.first?.ocrText == "detected text"
        }
    }

    func testClearRemovesItemsAndAssociatedFiles() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let textFilename = try XCTUnwrap(store.saveText("persisted body"))
        let imageFilename = try XCTUnwrap(store.saveImage(makePNGData()))

        store.add(.largeText(preview: "preview", filename: textFilename))
        store.add(.image(filename: imageFilename))

        await eventually { store.items.count == 2 }

        let textURL = paths.textsDirectory.appendingPathComponent(textFilename)
        let imageURL = paths.imagesDirectory.appendingPathComponent(imageFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: textURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))

        store.clear()

        await eventually { store.items.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: textURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }
}
