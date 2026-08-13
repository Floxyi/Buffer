import Foundation

struct HistoryDeleteRequest: Equatable, Sendable {
    let items: [ClipboardItem]
    let preferredSelectionID: UUID?

    var selectionCount: Int { items.count }
}

struct HistoryMutationFailure: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

@MainActor
struct HistoryItemMutationController {
    private let deletionPolicy = ClipboardDeletionPolicy()

    func makeDeleteRequest(
        for items: [ClipboardItem],
        in filteredItems: [ClipboardItem],
        selectionController: HistorySelectionController
    ) -> HistoryDeleteRequest? {
        let deletableItems = deletionPolicy.partition(items).deletable
        guard !deletableItems.isEmpty else { return nil }

        return HistoryDeleteRequest(
            items: deletableItems,
            preferredSelectionID: selectionController.preferredSelectionID(
                afterDeleting: deletableItems,
                from: filteredItems
            )
        )
    }

    func delete(
        _ request: HistoryDeleteRequest,
        store: ClipboardStore
    ) async throws -> UUID? {
        guard !request.items.isEmpty else { return nil }

        try await store.delete(request.items)
        return request.preferredSelectionID
    }

    func togglePinForSelectedItems(
        _ items: [ClipboardItem],
        store: ClipboardStore
    ) async throws {
        guard !items.isEmpty else { return }

        let pinState: ClipboardPinState = items.allSatisfy(\.isPinned) ? .unpinned : .pinned
        try await store.updatePinState(pinState, for: items)
    }

    func toggleBookmarkForSelectedItems(
        _ items: [ClipboardItem],
        store: ClipboardStore
    ) async throws {
        guard !items.isEmpty else { return }

        let bookmarkState: ClipboardBookmarkState =
            items.allSatisfy(\.isBookmarked)
            ? .notBookmarked
            : .bookmarked
        try await store.updateBookmarkState(bookmarkState, for: items)
    }
}
