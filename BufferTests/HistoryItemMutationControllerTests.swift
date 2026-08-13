import XCTest

@testable import Buffer

@MainActor
final class HistoryItemMutationControllerTests: XCTestCase {
    func testTogglePinForSelectedItemsPinsAllTargets() async throws {
        let controller = HistoryItemMutationController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        try await store.add(first)
        try await store.add(second)
        await eventually {
            store.items.count == 2
        }

        try await controller.togglePinForSelectedItems(
            [first, second],
            store: store
        )

        await eventually {
            store.items.allSatisfy(\.isPinned)
        }
    }

    func testDeleteRequestPrefersAdjacentSelectionAndDeletesTargets() async throws {
        let controller = HistoryItemMutationController()
        let selectionController = HistorySelectionController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        let third = ClipboardItem.text("third")
        try await store.add(first)
        try await store.add(second)
        try await store.add(third)
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
        let preferredSelectionID = try await controller.delete(
            request,
            store: store
        )

        await eventually {
            store.items.count == 2
        }
        XCTAssertEqual(Set(store.items.map(\.id)), [first.id, third.id])
        XCTAssertEqual(preferredSelectionID, first.id)
    }

    func testDeleteRequestFiltersProtectedItemsAtTheDomainBoundary() throws {
        let controller = HistoryItemMutationController()
        let ordinary = ClipboardItem.text("ordinary")
        let protected = ClipboardItem(
            isBookmarked: true,
            content: .text(TextItemContent(inlineText: "protected"))
        )

        let request = try XCTUnwrap(
            controller.makeDeleteRequest(
                for: [protected, ordinary],
                in: [protected, ordinary],
                selectionController: HistorySelectionController()
            )
        )

        XCTAssertEqual(request.items.map(\.id), [ordinary.id])
    }

    func testTogglePinForSelectedItemsUpdatesExactTargets() async throws {
        let controller = HistoryItemMutationController()
        let store = makeStore()
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")
        try await store.add(first)
        try await store.add(second)
        await eventually {
            store.items.count == 2
        }

        try await controller.togglePinForSelectedItems(
            [second],
            store: store
        )

        await eventually {
            store.items.first(where: { $0.id == second.id })?.isPinned == true
        }
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        return ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
    }
}
