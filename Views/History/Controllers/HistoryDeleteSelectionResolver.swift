import Foundation

struct HistoryDeleteSelectionResolver {
    func preferredSelectionID(
        afterDeleting items: [ClipboardItem],
        from filteredItems: [ClipboardItem]
    ) -> UUID? {
        let deletedIDs = Set(items.map(\.id))
        guard !deletedIDs.isEmpty else { return nil }

        let remainingItems = filteredItems.filter { !deletedIDs.contains($0.id) }
        guard !remainingItems.isEmpty else { return nil }

        let deletedIndices = items.compactMap { item in
            filteredItems.firstIndex(where: { $0.id == item.id })
        }

        guard let deletedIndex = deletedIndices.min() else {
            return remainingItems.first?.id
        }

        if let nextVisible = filteredItems[deletedIndex...].first(where: { !deletedIDs.contains($0.id) }) {
            return nextVisible.id
        }

        if deletedIndex > 0 {
            return filteredItems[0..<deletedIndex].last(where: { !deletedIDs.contains($0.id) })?.id
        }

        return remainingItems.first?.id
    }
}
