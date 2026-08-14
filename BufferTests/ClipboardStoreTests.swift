import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testAddEvictsOldestDeletableItemWhileKeepingPinnedAndBookmarkedItems() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryLimit(3)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let pinned = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(),
            content: .text(TextItemContent(inlineText: "pinned"))
        )
        let bookmarked = ClipboardItem(
            isBookmarked: true,
            bookmarkedAt: Date(),
            content: .text(TextItemContent(inlineText: "bookmarked"))
        )
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        try await store.add(pinned)
        try await store.add(first)
        try await store.add(bookmarked)
        try await store.add(second)

        await eventually {
            Set(store.items.map(\.id)) == [pinned.id, bookmarked.id, second.id]
        }
        XCTAssertFalse(store.items.contains { $0.id == first.id })
    }

    func testTogglePinSetsAndClearsPinnedState() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("pin me")

        try await store.add(item)
        await eventually { store.items.count == 1 }

        try await store.togglePin(for: item)
        await eventually {
            store.items.first?.isPinned == true && store.items.first?.pinnedAt != nil
        }

        let pinnedItem = try! XCTUnwrap(store.items.first)
        try await store.togglePin(for: pinnedItem)
        await eventually {
            store.items.first?.isPinned == false && store.items.first?.pinnedAt == nil
        }
    }

    func testToggleBookmarkDoesNotChangePinnedState() async throws {
        let store = makeStore()
        let item = ClipboardItem.text("bookmark me")
        try await store.add(item)
        await eventually { store.items.count == 1 }

        try await store.toggleBookmark(for: item)

        await eventually {
            store.items.first?.isBookmarked == true
                && store.items.first?.bookmarkedAt != nil
        }
        let bookmarked = try XCTUnwrap(store.items.first)
        XCTAssertFalse(bookmarked.isPinned)

        try await store.toggleBookmark(for: bookmarked)

        await eventually {
            store.items.first?.isBookmarked == false
                && store.items.first?.bookmarkedAt == nil
        }
    }

    func testDirectDeleteAndClearPreserveProtectedItems() async throws {
        let store = makeStore()
        let pinned = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(),
            content: .text(TextItemContent(inlineText: "pinned"))
        )
        let bookmarked = ClipboardItem(
            isBookmarked: true,
            bookmarkedAt: Date(),
            content: .text(TextItemContent(inlineText: "bookmarked"))
        )
        let ordinary = ClipboardItem.text("ordinary")
        try await store.add(pinned)
        try await store.add(bookmarked)
        try await store.add(ordinary)
        await eventually { store.items.count == 3 }

        try await store.delete([pinned, bookmarked, ordinary])

        await eventually { store.items.count == 2 }
        XCTAssertEqual(Set(store.items.map(\.id)), [pinned.id, bookmarked.id])

        try await store.clear()
        await Task.yield()
        XCTAssertEqual(Set(store.items.map(\.id)), [pinned.id, bookmarked.id])
    }

    func testDeleteUsesCurrentProtectionStateInsteadOfStaleCallerSnapshot() async throws {
        let store = makeStore()
        let protectedItem = ClipboardItem.text("protect me")
        let ordinaryItem = ClipboardItem.text("delete me")
        try await store.add(protectedItem)
        try await store.add(ordinaryItem)
        await eventually { store.items.count == 2 }

        try await store.toggleBookmark(for: protectedItem)
        await eventually {
            store.items.first(where: { $0.id == protectedItem.id })?.isBookmarked == true
        }

        try await store.delete([protectedItem, ordinaryItem])

        await eventually { store.items.count == 1 }
        XCTAssertEqual(store.items.first?.id, protectedItem.id)
    }

    func testMoveToTopReordersExistingItems() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let first = ClipboardItem.text("one")
        let second = ClipboardItem.text("two")
        let third = ClipboardItem.text("three")

        try await store.add(first)
        try await store.add(second)
        try await store.add(third)

        await eventually {
            store.items.map(\.textContent) == ["three", "two", "one"]
        }

        try await store.moveToTop(first)

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

        try await store.add(item)
        await eventually { store.items.count == 1 }

        try await store.setOCRText("detected text", for: item)

        await eventually {
            store.items.first?.ocrText == "detected text"
        }
        await store.waitForSearchIndex()

        XCTAssertEqual(store.searchableText(for: item), "detected text")
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

        try await store.add(.largeText(preview: "preview", filename: textFilename))
        try await store.add(.image(filename: imageFilename))

        await eventually { store.items.count == 2 }

        let textURL = paths.textsDirectory.appendingPathComponent(textFilename)
        let imageURL = paths.imagesDirectory.appendingPathComponent(imageFilename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: textURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))

        try await store.clear()

        await eventually { store.items.isEmpty }
        XCTAssertFalse(FileManager.default.fileExists(atPath: textURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }

    func testFailedPersistenceDoesNotPublishUncommittedMutation() async {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let store = ClipboardStore(
            settingsManager: SettingsManager(
                defaults: makeTestDefaults(),
                launchAtLoginController: FakeLaunchAtLoginController()
            ),
            assetStore: assetStore,
            persistence: FailingClipboardHistoryPersistence()
        )

        do {
            try await store.add(.text("must not publish"))
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Expected persistence failure")
        }
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        return ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
    }
}

private struct FailingClipboardHistoryPersistence: ClipboardHistoryPersisting {
    struct ExpectedFailure: LocalizedError {
        var errorDescription: String? { "Expected persistence failure" }
    }

    func loadHistory() throws -> [ClipboardItem] { [] }

    func saveHistory(_ items: [ClipboardItem]) throws {
        throw ExpectedFailure()
    }
}
