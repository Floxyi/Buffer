import Foundation

struct HistoryItemFilter {
    func filteredItems(
        from items: [ClipboardItem],
        query: String,
        searchIndex: ClipboardSearchIndex
    ) -> [ClipboardItem] {
        results(from: items, query: ClipboardQuery(text: query), searchIndex: searchIndex).map(\.item)
    }

    func results(
        from items: [ClipboardItem],
        query: ClipboardQuery,
        searchIndex: ClipboardSearchIndex
    ) -> [(item: ClipboardItem, result: ClipboardSearchResult)] {
        guard !query.isEmpty else {
            return items.map {
                ($0, ClipboardSearchResult(itemID: $0.id, score: 0, matches: []))
            }
        }

        return BufferPerformanceDiagnostics.measure(.historyFilter) {
            let eligibleItems = items.filter(query.filters.matches)
            guard !query.normalizedText.isEmpty else {
                return eligibleItems.map {
                    ($0, ClipboardSearchResult(itemID: $0.id, score: 0, matches: []))
                }
            }

            let resultsByItemID = searchIndex.results(
                for: eligibleItems.map(\.id),
                query: query
            )
            return eligibleItems.compactMap { item in
                resultsByItemID[item.id].map { (item, $0) }
            }
        }
    }
}
