import XCTest
@testable import Buffer

@MainActor
final class HistoryVisibleItemsControllerTests: XCTestCase {
    func testHandleStoreItemsChangeConsumesPendingSelectionAndRebuildsFilteredItems() {
        let controller = HistoryVisibleItemsController()
        let store = makeStore()
        let matching = ClipboardItem.text("match me")
        let other = ClipboardItem.text("ignore me")

        let update = controller.handleStoreItemsChange(
            items: [matching, other],
            searchText: "match",
            store: store,
            sessionState: HistorySessionState(
                isApplyingProgrammaticSearchChange: false,
                pendingPreferredSelectionID: matching.id
            )
        )

        XCTAssertEqual(update.filteredItems.map(\.id), [matching.id])
        XCTAssertEqual(update.preferredSelectionID, matching.id)
        XCTAssertNil(update.sessionState.pendingPreferredSelectionID)
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let paths = TestStorageFactory.makePaths()
        return ClipboardStore(settingsManager: settings, storagePaths: paths)
    }
}
