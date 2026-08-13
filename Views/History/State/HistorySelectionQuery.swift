import Foundation

struct HistorySelectionQuery {
    let filteredItems: [ClipboardItem]
    let selectedIDs: Set<UUID>
    let selectedActionOrderIDs: [UUID]
    let selectedID: UUID?
    let isQueryEmpty: Bool
    let totalItemCount: Int
    private let itemByID: [UUID: ClipboardItem]
    private let itemIndexByID: [UUID: Int]

    init(
        filteredItems: [ClipboardItem],
        selectedIDs: Set<UUID>,
        selectedActionOrderIDs: [UUID],
        selectedID: UUID?,
        isQueryEmpty: Bool,
        totalItemCount: Int,
        itemByID: [UUID: ClipboardItem]? = nil,
        itemIndexByID: [UUID: Int]? = nil
    ) {
        self.filteredItems = filteredItems
        self.selectedIDs = selectedIDs
        self.selectedActionOrderIDs = selectedActionOrderIDs
        self.selectedID = selectedID
        self.isQueryEmpty = isQueryEmpty
        self.totalItemCount = totalItemCount
        self.itemByID = itemByID ?? Dictionary(uniqueKeysWithValues: filteredItems.map { ($0.id, $0) })
        self.itemIndexByID =
            itemIndexByID
            ?? Dictionary(uniqueKeysWithValues: filteredItems.enumerated().map { ($1.id, $0) })
    }

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return nil }
        return itemByID[selectedID]
    }

    var selectedItems: [ClipboardItem] {
        selectedIDs
            .compactMap { id -> (index: Int, item: ClipboardItem)? in
                guard let index = itemIndexByID[id], let item = itemByID[id] else { return nil }
                return (index, item)
            }
            .sorted { $0.index < $1.index }
            .map(\.item)
    }

    var selectedItemsInActionOrder: [ClipboardItem] {
        return selectedActionOrderIDs.compactMap { id in
            guard selectedIDs.contains(id) else { return nil }
            return itemByID[id]
        }
    }

    var selectionCount: Int {
        selectedIDs.count
    }

    var isShowingFullHistory: Bool {
        isQueryEmpty && filteredItems.count == totalItemCount
    }
}
