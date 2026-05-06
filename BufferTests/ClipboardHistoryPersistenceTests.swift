import Foundation
import XCTest
@testable import Buffer

final class ClipboardHistoryPersistenceTests: XCTestCase {
    func testSaveHistoryWritesVersionedEnvelopeAndRoundTrips() throws {
        let paths = TestStorageFactory.makePaths()
        let persistence = ClipboardHistoryPersistence(paths: paths)
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let items = [ClipboardItem.text("hello")]
        persistence.saveHistory(items)

        let data = try Data(contentsOf: paths.historyFileURL)
        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: data)

        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(persistence.loadHistory(), items)
    }

    func testLoadHistorySupportsLegacyArrayPayload() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let items = [ClipboardItem.text("legacy")]
        let data = try JSONEncoder().encode(items)
        try data.write(to: paths.historyFileURL, options: .atomic)

        let persistence = ClipboardHistoryPersistence(paths: paths)
        XCTAssertEqual(persistence.loadHistory(), items)
    }

    @MainActor
    func testPendingFileBackedTextAssetSurvivesUntilItemIsAdded() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let filename = try XCTUnwrap(store.saveText("file-backed body"))
        let fileURL = paths.textsDirectory.appendingPathComponent(filename)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.add(.text("inline item"))
        await eventually {
            store.items.count == 1
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.add(.largeText(preview: "preview", filename: filename))
        await eventually {
            store.items.count == 2
        }

        let storedItem = try XCTUnwrap(store.items.first(where: { $0.textFilename == filename }))
        XCTAssertEqual(store.fullText(for: storedItem), "file-backed body")
    }
}

private struct TestEnvelope: Codable {
    let version: Int
    let items: [ClipboardItem]
}
