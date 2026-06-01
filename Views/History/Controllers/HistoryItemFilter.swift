import Foundation

@MainActor
struct HistoryItemFilter {
    func filteredItems(
        from items: [ClipboardItem],
        query: String,
        store: ClipboardStore
    ) -> [ClipboardItem] {
        let baseItems: [ClipboardItem]

        if query.isEmpty {
            baseItems = items
        } else {
            baseItems = items.filter { item in
                store.searchableText(for: item).localizedCaseInsensitiveContains(query)
            }
        }

        return baseItems.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }

            if lhs.isPinned, rhs.isPinned {
                let lhsPinnedAt = lhs.pinnedAt ?? lhs.timestamp
                let rhsPinnedAt = rhs.pinnedAt ?? rhs.timestamp

                if lhsPinnedAt != rhsPinnedAt {
                    return lhsPinnedAt < rhsPinnedAt
                }
            }

            return lhs.timestamp > rhs.timestamp
        }
    }
}
