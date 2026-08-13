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
            items.compactMap { item in
                guard let result = searchIndex.result(for: item, query: query) else {
                    return nil
                }
                return (item, result)
            }
        }
    }
}
