import Foundation

struct ClipboardSearchIndex {
    struct Entry {
        let contentHash: Int
        let searchableText: String
        let normalizedSearchableText: String
    }

    private var cache: [UUID: Entry] = [:]

    mutating func rebuild(
        using items: [ClipboardItem],
        loader: (ClipboardItem) -> String
    ) {
        let validIDs = Set(items.map(\.id))
        cache = cache.filter { validIDs.contains($0.key) }

        for item in items {
            if let cached = cache[item.id], cached.contentHash == item.contentHash {
                continue
            }

            let searchableText = loader(item)
            cache[item.id] = Entry(
                contentHash: item.contentHash,
                searchableText: searchableText,
                normalizedSearchableText: Self.normalize(searchableText)
            )
        }
    }

    func searchableText(for itemID: UUID) -> String {
        cache[itemID]?.searchableText ?? ""
    }

    func hasEntry(for itemID: UUID) -> Bool {
        cache[itemID] != nil
    }

    func matches(_ normalizedQuery: String, for itemID: UUID) -> Bool {
        guard !normalizedQuery.isEmpty else {
            return true
        }

        return cache[itemID]?.normalizedSearchableText.contains(normalizedQuery) == true
    }

    mutating func store(_ searchableText: String, for item: ClipboardItem) {
        cache[item.id] = Entry(
            contentHash: item.contentHash,
            searchableText: searchableText,
            normalizedSearchableText: Self.normalize(searchableText)
        )
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
