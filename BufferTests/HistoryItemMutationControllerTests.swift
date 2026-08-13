import XCTest
@testable import Buffer

@MainActor
final class HistoryItemMutationControllerTests: XCTestCase {
    func testTogglePinForSelectedItemsPinsAllTargetsAndSyncsPreferredSelection() async {
        let controller = HistoryItemMutationController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        var syncedSelectionID: UUID?

        store.add(first)
        store.add(second)
        await eventually {
            store.items.count == 2
        }

        controller.togglePinForSelectedItems(
            [first, second],
            selectedID: second.id,
            store: store,
            syncSelection: { syncedSelectionID = $0 }
        )

        await eventually {
            store.items.allSatisfy(\.isPinned)
        }
        XCTAssertEqual(syncedSelectionID, second.id)
    }

    func testDeleteRequestPrefersAdjacentSelectionAndDeletesTargets() async throws {
        let controller = HistoryItemMutationController()
        let selectionController = HistorySelectionController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let third = ClipboardItem.text("third")
        var pendingPreferredSelectionID: UUID?

        store.add(first)
        store.add(second)
        store.add(third)
        await eventually {
            store.items.count == 3
        }

        let filteredItems = [third, second, first]
        let request = try XCTUnwrap(
            controller.makeDeleteRequest(
                for: [second],
                in: filteredItems,
                selectionController: selectionController
            )
        )
        controller.delete(
            request,
            store: store,
            setPendingPreferredSelectionID: { pendingPreferredSelectionID = $0 }
        )

        await eventually {
            store.items.count == 2
        }
        XCTAssertEqual(Set(store.items.map(\.id)), [first.id, third.id])
        XCTAssertEqual(pendingPreferredSelectionID, first.id)
    }

    func testTogglePinForContextMenuTargetUsesClickedItemWhenNotAlreadySelected() async {
        let controller = HistoryItemMutationController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        var syncedSelectionID: UUID?

        store.add(first)
        store.add(second)
        await eventually {
            store.items.count == 2
        }

        controller.togglePinForContextMenuTarget(
            [second],
            clickedItemID: second.id,
            selectedIDs: [first.id],
            selectedID: first.id,
            store: store,
            syncSelection: { syncedSelectionID = $0 }
        )

        await eventually {
            store.items.first(where: { $0.id == second.id })?.isPinned == true
        }
        XCTAssertEqual(syncedSelectionID, second.id)
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        return ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
    }
}
