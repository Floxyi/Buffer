import XCTest

@testable import Buffer

@MainActor
func makeHistoryTestSettings(testName: String = UUID().uuidString) -> SettingsManager {
    SettingsManager(
        defaults: makeTestDefaults(testName: testName),
        launchAtLoginController: FakeLaunchAtLoginController()
    )
}

@MainActor
func makeHistoryTestStore(
    settings: SettingsManager,
    testName: String = UUID().uuidString,
    searchIndexer: (any ClipboardSearchIndexing)? = nil
) -> ClipboardStore {
    let storagePaths = TestStorageFactory.makePaths(testName: testName)
    if let searchIndexer {
        return ClipboardStore(
            settingsManager: settings,
            storagePaths: storagePaths,
            searchIndexer: searchIndexer
        )
    }
    return ClipboardStore(settingsManager: settings, storagePaths: storagePaths)
}

@MainActor
func makeHistoryTestViewModel(
    store: ClipboardStore,
    settings: SettingsManager,
    ocrResult: String? = ""
) -> HistoryViewModel {
    HistoryViewModel(
        store: store,
        settingsManager: settings,
        ocrService: FakeOCRService(result: ocrResult)
    )
}

@MainActor
func populateStore(_ store: ClipboardStore, with items: [ClipboardItem]) async {
    do {
        for item in items {
            try await store.add(item)
        }
    } catch {
        XCTFail("Failed to populate clipboard history: \(error.localizedDescription)")
        return
    }

    await eventually {
        store.items.count == items.count
    }
    await store.waitForSearchIndex()
}

@MainActor
func makeSelectionHistoryViewModel() async -> HistoryViewModel {
    let settings = makeHistoryTestSettings()
    let store = makeHistoryTestStore(settings: settings)

    let oldest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "oldest")
    let middle = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "middle")
    let newest = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "newest")

    await populateStore(store, with: [oldest, middle, newest])

    return makeHistoryTestViewModel(store: store, settings: settings)
}
