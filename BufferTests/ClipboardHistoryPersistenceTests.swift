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

    func testClipboardItemRoundTripsStructuredColorPayload() throws {
        let colorItem = ClipboardItem.color(
            ClipboardColorValue(red: 1, green: 0, blue: 0.5, alpha: 1),
            originalText: "rgb(255, 0, 128)"
        )

        let data = try JSONEncoder().encode(colorItem)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.kind, .color)
        XCTAssertEqual(decoded.colorPayload?.originalText, "rgb(255, 0, 128)")
        XCTAssertEqual(decoded.colorPayload?.value, colorItem.colorPayload?.value)
    }

    func testClipboardItemRoundTripsStructuredLinkPayload() throws {
        let linkURL = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=123"))
        let linkItem = ClipboardItem.link(linkURL, originalText: "youtube.com/watch?v=123")

        let data = try JSONEncoder().encode(linkItem)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)

        XCTAssertEqual(decoded.kind, .link)
        XCTAssertEqual(decoded.linkPayload?.originalText, "youtube.com/watch?v=123")
        XCTAssertEqual(decoded.linkPayload?.url, linkURL)
        XCTAssertEqual(decoded.linkPayload?.websiteName, "Youtube")
    }

    func testClipboardColorValueFormatsOpaqueVariants() {
        let colorValue = ClipboardColorValue(red: 1, green: 0, blue: 0.5, alpha: 1)

        XCTAssertEqual(colorValue.formatted(as: .hex), "#FF0080")
        XCTAssertEqual(colorValue.formatted(as: .rgb), "rgb(255, 0, 128)")
        XCTAssertEqual(colorValue.formatted(as: .hsl), "hsl(330, 100%, 50%)")
    }

    func testClipboardColorValueFormatsTransparentVariants() {
        let colorValue = ClipboardColorValue(red: 1, green: 0, blue: 0, alpha: 0.5)

        XCTAssertEqual(colorValue.formatted(as: .hex), "#FF000080")
        XCTAssertEqual(colorValue.formatted(as: .rgb), "rgba(255, 0, 0, 0.5)")
        XCTAssertEqual(colorValue.formatted(as: .hsl), "hsla(0, 100%, 50%, 0.5)")
    }

    @MainActor
    func testStoreDropsExpiredHistoryEntriesOnLoadWhenRetentionIsEnabled() async throws {
        let paths = TestStorageFactory.makePaths()
        let persistence = ClipboardHistoryPersistence(paths: paths)
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()

        let freshItem = ClipboardItem.text("fresh")
        let expiredItem = ClipboardItem(
            type: .text,
            timestamp: Date().addingTimeInterval(-(13 * 60 * 60)),
            textContent: "expired"
        )
        persistence.saveHistory([freshItem, expiredItem])

        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryRetentionPeriod(.twelveHours)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        XCTAssertEqual(store.items.map(\.id), [freshItem.id])
        XCTAssertEqual(persistence.loadHistory().map(\.id), [freshItem.id])
    }

    @MainActor
    func testStorePrunesExpiredHistoryEntriesWhenRetentionSettingChanges() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)

        let expiredItem = ClipboardItem(
            type: .text,
            timestamp: Date().addingTimeInterval(-(8 * 24 * 60 * 60)),
            textContent: "expired"
        )
        let freshItem = ClipboardItem.text("fresh")

        store.add(expiredItem)
        store.add(freshItem)

        await eventually {
            store.items.count == 2
        }

        settings.setHistoryRetentionPeriod(.oneWeek)

        await eventually {
            store.items.map(\.id) == [freshItem.id]
        }
    }

    @MainActor
    func testStoreAllowsHistoryToGrowAfterIncreasingLimit() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryLimit(2)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let first = ClipboardItem.text("one")
        let second = ClipboardItem.text("two")
        let third = ClipboardItem.text("three")
        let fourth = ClipboardItem.text("four")

        store.add(first)
        store.add(second)
        await eventually {
            store.items.map(\.textContent) == ["two", "one"]
        }

        settings.setHistoryLimit(4)
        store.add(third)
        store.add(fourth)

        await eventually {
            store.items.map(\.textContent) == ["four", "three", "two", "one"]
        }
    }

    @MainActor
    func testStoreTrimsHistoryWhenLimitShrinks() async throws {
        let paths = TestStorageFactory.makePaths()
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        settings.setHistoryLimit(4)

        let store = ClipboardStore(settingsManager: settings, storagePaths: paths)
        let first = ClipboardItem.text("one")
        let second = ClipboardItem.text("two")
        let third = ClipboardItem.text("three")
        let fourth = ClipboardItem.text("four")

        store.add(first)
        store.add(second)
        store.add(third)
        store.add(fourth)

        await eventually {
            store.items.map(\.textContent) == ["four", "three", "two", "one"]
        }

        settings.setHistoryLimit(2)

        await eventually {
            store.items.map(\.textContent) == ["four", "three"]
        }
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
