import Foundation

@MainActor
struct HistoryItemFilter {
    func filteredItems(
        from items: [ClipboardItem],
        query: String,
        store: ClipboardStore
    ) -> [ClipboardItem] {
        let normalizedQuery = ClipboardSearchIndex.normalize(query)
        guard !normalizedQuery.isEmpty else {
            return items
        }

        return BufferPerformanceDiagnostics.measure(.historyFilter) {
            items.filter { item in
                store.matchesSearchQuery(normalizedQuery, for: item)
            }
        }
    }
}
