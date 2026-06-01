import Foundation

struct HistorySelectionQuery {
    let filteredItems: [ClipboardItem]
    let selectedIDs: Set<UUID>
    let selectedActionOrderIDs: [UUID]
    let selectedID: UUID?
    let searchText: String
    let totalItemCount: Int

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return filteredItems.first(where: { $0.id == selectedID })
    }

    var selectedItems: [ClipboardItem] {
        filteredItems.filter { selectedIDs.contains($0.id) }
    }

    var selectedItemsInActionOrder: [ClipboardItem] {
        let itemsByID = Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
        return selectedActionOrderIDs.compactMap { id in
            guard selectedIDs.contains(id) else { return nil }
            return itemsByID[id]
        }
    }

    var selectionCount: Int {
        selectedIDs.count
    }

    var isShowingFullHistory: Bool {
        searchText.isEmpty && filteredItems.count == totalItemCount
    }
}
