import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ClipboardStoreTests: XCTestCase {
    func testReorderPinnedItemsPersistsOnlyPinnedSlotPermutation() async throws {
        let paths = TestStorageFactory.makePaths()
        try FileManager.default.createDirectory(
            at: paths.storageDirectory,
            withIntermediateDirectories: true
        )
        let unpinnedA = ClipboardItem.text("unpinned-a")
        let unpinnedB = ClipboardItem.text("unpinned-b")
        let unpinnedC = ClipboardItem.text("unpinned-c")
        let pinnedA = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 1),
            content: .text(TextItemContent(inlineText: "pinned-a"))
        )
        let pinnedB = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 2),
            content: .text(TextItemContent(inlineText: "pinned-b"))
        )
        let pinnedC = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 3),
            content: .text(TextItemContent(inlineText: "pinned-c"))
        )
        let persistence = ClipboardHistoryPersistence(paths: paths)
        try persistence.saveHistory([
            unpinnedA, pinnedA, unpinnedB, pinnedB, unpinnedC, pinnedC,
        ])
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let originalRevision = store.currentHistoryRevision

        try await store.reorderPinnedItems(
            ClipboardPinnedReorderRequest(
                movingItemIDs: [pinnedC.id],
                destination: .before(pinnedA.id)
            )
        )

        XCTAssertEqual(
            store.items.map(\.id),
            [pinnedC.id, pinnedA.id, pinnedB.id, unpinnedA.id, unpinnedB.id, unpinnedC.id]
        )
        XCTAssertEqual(store.currentHistoryRevision, originalRevision)
        let persistedItems = try persistence.loadHistory()
        XCTAssertEqual(
            persistedItems.map(\.id),
            [unpinnedA.id, pinnedC.id, unpinnedB.id, pinnedA.id, unpinnedC.id, pinnedB.id]
        )
        XCTAssertEqual(
            persistedItems.filter(\.isPinned).map(\.pinnedAt),
            [pinnedC.pinnedAt, pinnedA.pinnedAt, pinnedB.pinnedAt]
        )
    }

    func testRepositoryReorderCommitsOnceWithoutSearchChanges() async throws {
        let paths = TestStorageFactory.makePaths()
        let first = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 1),
            content: .text(TextItemContent(inlineText: "first"))
        )
        let second = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 2),
            content: .text(TextItemContent(inlineText: "second"))
        )
        let persistence = RecordingClipboardHistoryPersistence(initialItems: [first, second])
        let repository = ClipboardRepository(
            initialItems: [first, second],
            persistence: persistence,
            assetStore: ClipboardAssetStore(paths: paths)
        )

        let mutation = try await repository.reorderPinnedItems(
            ClipboardPinnedReorderRequest(
                movingItemIDs: [second.id],
                destination: .before(first.id)
            )
        )

        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(mutation.snapshot.map(\.id), [second.id, first.id])
        XCTAssertEqual(mutation.historyRevision, 0)
        XCTAssertTrue(mutation.searchChangeSet.isEmpty)
    }

    func testRepositoryReorderKeepsAuthoritativeOrderWhenPersistenceFails() async throws {
        let paths = TestStorageFactory.makePaths()
        let first = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 1),
            content: .text(TextItemContent(inlineText: "first"))
        )
        let second = ClipboardItem(
            isPinned: true,
            pinnedAt: Date(timeIntervalSince1970: 2),
            content: .text(TextItemContent(inlineText: "second"))
        )
        let repository = ClipboardRepository(
            initialItems: [first, second],
            persistence: FailingClipboardHistoryPersistence(),
            assetStore: ClipboardAssetStore(paths: paths)
        )

        do {
            _ = try await repository.reorderPinnedItems(
                ClipboardPinnedReorderRequest(
                    movingItemIDs: [second.id],
                    destination: .before(first.id)
                )
            )
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Expected persistence failure")
        }

        let snapshot = await repository.snapshot()
        let historyRevision = await repository.currentHistoryRevision()
        XCTAssertEqual(snapshot.map(\.id), [first.id, second.id])
        XCTAssertEqual(historyRevision, 0)
    }

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

        let searchableText = await store.searchableText(for: item)
        XCTAssertEqual(searchableText, "detected text")
        let response = try await store.search(ClipboardQuery(text: "detected text"), generation: 1)
        XCTAssertTrue(response.hits.contains { $0.itemID == item.id })
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
            persistence: FailingClipboardHistoryPersistence(),
            searchService: ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        )

        do {
            try await store.add(.text("must not publish"))
            XCTFail("Expected persistence failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Expected persistence failure")
        }
        XCTAssertTrue(store.items.isEmpty)
    }

    func testPersistentSearchFindsDeepMatchInLargeFileBackedTextAndReturnsContext() async throws {
        let store = makeStore()
        let body =
            String(repeating: "background content ", count: 80_000)
            + "deep-performance-needle"
            + String(repeating: " trailing content", count: 2_000)
        let filename = try XCTUnwrap(store.saveText(body))
        let item = ClipboardItem.largeText(preview: "background content", filename: filename)

        try await store.add(item)
        await store.waitForSearchIndex()

        let response = try await completeSearch(
            store,
            ClipboardQuery(text: "deep-performance-needle"),
            generation: 7
        )
        let hit = try XCTUnwrap(response.hits.first { $0.itemID == item.id })
        XCTAssertEqual(response.session.queryGeneration, 7)
        XCTAssertEqual(hit.evidence.kind.classification, .exact)
        XCTAssertNil(hit.snippet)

        let snippetBatch = try await store.snippets(
            ClipboardSearchSnippetRequest(
                session: response.session,
                itemIDs: [hit.itemID]
            )
        )
        let snippet = try XCTUnwrap(snippetBatch.snippetsByItemID[item.id])
        XCTAssertTrue(snippet.text.contains("deep-performance-needle"))
        XCTAssertTrue(snippet.segments.contains(where: \.isHighlighted))
        XCTAssertLessThanOrEqual(snippet.text.count, 120)
    }

    func testPersistentSearchUsesWordPrefixesForQueriesShorterThanThreeCharacters() async throws {
        let store = makeStore()
        let alpha = ClipboardItem.text("alpha value")
        let beta = ClipboardItem.text("beta value")
        try await store.add(alpha)
        try await store.add(beta)
        await store.waitForSearchIndex()

        let prefix = try await store.search(ClipboardQuery(text: "al"), generation: 1)
        let nonPrefix = try await store.search(ClipboardQuery(text: "ph"), generation: 2)

        XCTAssertEqual(Set(prefix.hits.map(\.itemID)), [alpha.id])
        XCTAssertTrue(nonPrefix.hits.isEmpty)
    }

    func testPersistentSearchDoesNotFuzzyExpandAnExactVocabularyTerm() async throws {
        let store = makeStore()
        let exact = ClipboardItem.text("receipt")
        let fuzzy = ClipboardItem.text("reciept")
        try await store.add(exact)
        try await store.add(fuzzy)
        await store.waitForSearchIndex()

        let response = try await store.search(ClipboardQuery(text: "receipt"), generation: 1)

        XCTAssertEqual(response.hits.first { $0.itemID == exact.id }?.rank.tier, .exactToken)
        XCTAssertFalse(response.hits.contains { $0.itemID == fuzzy.id })
    }

    func testPinningDoesNotScheduleSearchIndexWork() async throws {
        let store = makeStore()
        let item = ClipboardItem.text("stable searchable content")
        try await store.add(item)
        await store.waitForSearchIndex()
        let generation = store.searchStatus.generation

        try await store.togglePin(for: item)
        await eventually { store.items.first?.isPinned == true }

        XCTAssertEqual(store.searchStatus.generation, generation)
        XCTAssertEqual(store.currentHistoryRevision, 1)
        let response = try await store.search(
            ClipboardQuery(text: "stable searchable content"),
            generation: 99
        )
        XCTAssertEqual(response.hits.map(\.itemID), [item.id])
        XCTAssertEqual(
            response.session.committedState.historyRevision,
            store.currentHistoryRevision
        )
    }

    func testCorruptPersistentSearchDatabaseIsRebuilt() async throws {
        let paths = TestStorageFactory.makePaths()
        try FileManager.default.createDirectory(
            at: paths.searchDirectory,
            withIntermediateDirectories: true
        )
        try Data("not a sqlite database".utf8).write(to: paths.searchDatabaseURL)
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("recovered searchable value")

        try await store.add(item)
        await store.waitForSearchIndex()
        let response = try await store.search(ClipboardQuery(text: "recovered"), generation: 1)

        XCTAssertTrue(response.hits.contains { $0.itemID == item.id })
    }

    func testPersistentSearchDatabaseIsReusableAcrossStoreInstances() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let firstStore = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let item = ClipboardItem.text("persistent index value")
        try await firstStore.add(item)
        await firstStore.waitForSearchIndex()

        let secondStore = ClipboardStore(settingsManager: settings, storagePaths: paths)
        await secondStore.waitForSearchIndex()
        let response = try await secondStore.search(ClipboardQuery(text: "persistent index"), generation: 1)

        XCTAssertTrue(response.hits.contains { $0.itemID == item.id })
        XCTAssertTrue(secondStore.searchStatus.isReady)
    }

    func testMixedFieldPunctuationSearchesRemainResponsive() async throws {
        let store = makeStore()
        let inlineItem = ClipboardItem.text("inline needle")
        let filename = try XCTUnwrap(store.saveText("file-backed needle body"))
        let fileBackedItem = ClipboardItem.largeText(preview: "preview", filename: filename)
        let colorItem = ClipboardItem.color(
            ClipboardColorValue(red: 1, green: 0, blue: 0, alpha: 1),
            originalText: "#ff0000"
        )
        let linkItem = ClipboardItem.link(
            try XCTUnwrap(URL(string: "https://openai.com/research")),
            originalText: "openai.com/research"
        )
        let emailItem = ClipboardItem.email(try XCTUnwrap(ClipboardEmailValue.parse("person@example.com")))
        let imageItem = ClipboardItem(type: .image, imageFilename: "image.png", ocrText: "ocr needle text")
        for item in [inlineItem, fileBackedItem, colorItem, linkItem, emailItem, imageItem] {
            try await store.add(item)
        }
        await store.waitForSearchIndex()

        for (generation, query, expectedID) in [
            (1, "file-backed", fileBackedItem.id),
            (2, "ocr needle", imageItem.id),
            (3, "orc needel", imageItem.id),
            (4, "inline needle", inlineItem.id),
            (5, "#ff0000", colorItem.id),
            (6, "openai.com/research", linkItem.id),
            (7, "person@example.com", emailItem.id),
        ] {
            let start = CFAbsoluteTimeGetCurrent()
            let response = try await completeSearch(
                store,
                ClipboardQuery(text: query),
                generation: UInt(generation)
            )
            let duration = CFAbsoluteTimeGetCurrent() - start
            XCTAssertEqual(response.hits.map(\.itemID), [expectedID], query)
            XCTAssertLessThan(
                duration,
                1,
                "\(query) took \(duration)s; status=\(store.searchStatus)"
            )
        }
    }

    func testResetLoadsEachFileBackedAssetOnlyOnceBeforeItsTransaction() async throws {
        let paths = TestStorageFactory.makePaths()
        let assetAccess = CountingSearchAssetAccess(text: "complete file-backed body")
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let item = ClipboardItem(
            content: .text(TextItemContent(inlineText: "preview", fileName: "immutable.txt"))
        )

        _ = await service.reconcile(
            snapshot: [item],
            historyRevision: 1,
            assetAccess: assetAccess
        )
        XCTAssertEqual(assetAccess.searchReadCount, 1)

        _ = await service.apply(
            ClipboardSearchChangeSet(historyRevision: 2, changes: [.reset]),
            currentSnapshot: [item],
            assetAccess: assetAccess
        )

        XCTAssertEqual(assetAccess.searchReadCount, 1)
    }

    private func completeSearch(
        _ store: ClipboardStore,
        _ query: ClipboardQuery,
        generation: UInt
    ) async throws -> ClipboardSearchResponse {
        try await store.search(query, generation: generation)
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

final class ClipboardPinnedOrderResolverTests: XCTestCase {
    private let resolver = ClipboardPinnedOrderResolver()

    func testMovesSingleItemBeforeAnotherItem() throws {
        let ids = makeIDs(4)

        let result = resolver.reorderedItemIDs(
            currentItemIDs: ids,
            request: ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[2]],
                destination: .before(ids[0])
            )
        )

        XCTAssertEqual(result, [ids[2], ids[0], ids[1], ids[3]])
    }

    func testMovesGroupInVisualOrderAndIgnoresDuplicatesAndStaleIDs() throws {
        let ids = makeIDs(5)

        let result = resolver.reorderedItemIDs(
            currentItemIDs: ids,
            request: ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[3], UUID(), ids[1], ids[3]],
                destination: .before(ids[0])
            )
        )

        XCTAssertEqual(result, [ids[1], ids[3], ids[0], ids[2], ids[4]])
    }

    func testMovingBeforeItemInsideGroupIsNoOp() throws {
        let ids = makeIDs(4)

        let result = resolver.reorderedItemIDs(
            currentItemIDs: ids,
            request: ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[1], ids[2]],
                destination: .before(ids[2])
            )
        )

        XCTAssertNil(result)
    }

    func testMovesGroupToEnd() throws {
        let ids = makeIDs(5)

        let result = resolver.reorderedItemIDs(
            currentItemIDs: ids,
            request: ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[0], ids[2]],
                destination: .end
            )
        )

        XCTAssertEqual(result, [ids[1], ids[3], ids[4], ids[0], ids[2]])
    }

    private func makeIDs(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }
}

private final class CountingSearchAssetAccess: ClipboardAssetAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let text: String
    private var readCount = 0

    init(text: String) {
        self.text = text
    }

    var searchReadCount: Int {
        lock.withLock { readCount }
    }

    func image(for item: ClipboardItem) -> NSImage? { nil }
    func imageData(for item: ClipboardItem) -> Data? { nil }
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? { nil }
    func imageDimensions(for item: ClipboardItem) -> String? { nil }
    func saveImage(_ data: Data) -> String? { nil }
    func saveText(_ text: String) -> String? { nil }
    func deleteImage(named filename: String) {}
    func deleteText(named filename: String) {}
    func fullText(for item: ClipboardItem) -> String? { text }

    func fingerprint(for item: ClipboardItem) throws -> ClipboardSearchAssetFingerprint {
        ClipboardSearchAssetFingerprint(
            fileIdentity: nil,
            byteCount: Int64(text.utf8.count),
            modificationNanoseconds: 0
        )
    }

    func snapshot(
        for item: ClipboardItem,
        checkCancellation: @Sendable () throws -> Void
    ) throws -> ClipboardSearchAssetSnapshot {
        try checkCancellation()
        lock.withLock { readCount += 1 }
        return ClipboardSearchAssetSnapshot(
            text: text,
            fingerprint: try fingerprint(for: item)
        )
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk? { nil }
    func itemSize(for item: ClipboardItem) -> Int? { text.utf8.count }
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

private final class RecordingClipboardHistoryPersistence:
    ClipboardHistoryPersisting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var items: [ClipboardItem]
    private var saves = 0

    init(initialItems: [ClipboardItem]) {
        self.items = initialItems
    }

    var saveCount: Int {
        lock.withLock { saves }
    }

    func loadHistory() throws -> [ClipboardItem] {
        lock.withLock { items }
    }

    func saveHistory(_ items: [ClipboardItem]) throws {
        lock.withLock {
            self.items = items
            saves += 1
        }
    }
}
