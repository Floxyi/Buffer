import Foundation

struct HistoryQuerySnapshot: Equatable {
    let id = UUID()
    var revision: UInt = 0
    var query = ClipboardQuery()
    var items: [ClipboardItem] = []
    var resultsByItemID: [UUID: ClipboardSearchResult] = [:]
}

struct HistoryQueryModel {
    private let itemFilter = HistoryItemFilter()

    func evaluate(
        items: [ClipboardItem],
        query: ClipboardQuery,
        searchIndex: ClipboardSearchIndex
    ) -> HistoryQuerySnapshot {
        let matches = itemFilter.results(from: items, query: query, searchIndex: searchIndex)
        return HistoryQuerySnapshot(
            revision: 0,
            query: query,
            items: matches.map(\.item),
            resultsByItemID: Dictionary(
                uniqueKeysWithValues: matches.map { ($0.item.id, $0.result) }
            )
        )
    }
}
