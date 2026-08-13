import Foundation

struct ClipboardSearchIndex: Sendable {
    struct Entry: Sendable {
        let contentHash: Int
        let contentText: String
        let normalizedContentText: String
        let sourceApplicationText: String
        let normalizedSourceApplicationText: String
        let ocrText: String
        let normalizedOCRText: String
    }

    private var cache: [UUID: Entry] = [:]

    mutating func rebuild(
        using items: [ClipboardItem],
        loader: (ClipboardItem) -> String
    ) {
        let validIDs = Set(items.map(\.id))
        cache = cache.filter { validIDs.contains($0.key) }

        for item in items {
            let sourceApplicationText = item.sourceAppDisplayName ?? ""
            let ocrText = item.ocrText ?? ""
            if let cached = cache[item.id],
                cached.contentHash == item.contentHash,
                cached.sourceApplicationText == sourceApplicationText,
                cached.ocrText == ocrText
            {
                continue
            }

            store(loader(item), for: item)
        }
    }

    func searchableText(for itemID: UUID) -> String {
        cache[itemID]?.contentText ?? ""
    }

    func hasEntry(for itemID: UUID) -> Bool {
        cache[itemID] != nil
    }

    func matches(_ normalizedQuery: String, for itemID: UUID) -> Bool {
        guard !normalizedQuery.isEmpty else {
            return true
        }

        guard let entry = cache[itemID] else { return false }
        return entry.normalizedContentText.contains(normalizedQuery)
            || entry.normalizedSourceApplicationText.contains(normalizedQuery)
            || entry.normalizedOCRText.contains(normalizedQuery)
    }

    func result(for item: ClipboardItem, query: ClipboardQuery) -> ClipboardSearchResult? {
        guard query.filters.matches(item), let entry = cache[item.id] else {
            return nil
        }

        let normalizedQuery = query.normalizedText
        guard !normalizedQuery.isEmpty else {
            return ClipboardSearchResult(itemID: item.id, score: 0, matches: [])
        }

        var matches: [ClipboardTextMatch] = []
        appendMatch(
            field: .content,
            originalText: entry.contentText,
            normalizedQuery: normalizedQuery,
            to: &matches
        )
        appendMatch(
            field: .sourceApplication,
            originalText: entry.sourceApplicationText,
            normalizedQuery: normalizedQuery,
            to: &matches
        )
        if query.includesOCRText {
            appendMatch(
                field: .ocr,
                originalText: entry.ocrText,
                normalizedQuery: normalizedQuery,
                to: &matches
            )
        }

        guard !matches.isEmpty else { return nil }
        let score = matches.reduce(0.0) { total, match in
            total + (match.field == .content ? 2 : 1)
        }
        return ClipboardSearchResult(itemID: item.id, score: score, matches: matches)
    }

    mutating func store(_ searchableText: String, for item: ClipboardItem) {
        let sourceApplicationText = item.sourceAppDisplayName ?? ""
        let ocrText = item.ocrText ?? ""
        cache[item.id] = Entry(
            contentHash: item.contentHash,
            contentText: searchableText,
            normalizedContentText: Self.normalize(searchableText),
            sourceApplicationText: sourceApplicationText,
            normalizedSourceApplicationText: Self.normalize(sourceApplicationText),
            ocrText: ocrText,
            normalizedOCRText: Self.normalize(ocrText)
        )
    }

    private func appendMatch(
        field: ClipboardMatchField,
        originalText: String,
        normalizedQuery: String,
        to matches: inout [ClipboardTextMatch]
    ) {
        var ranges: [Range<String.Index>] = []
        var remainingRange = originalText.startIndex..<originalText.endIndex
        while let range = originalText.range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remainingRange
        ) {
            ranges.append(range)
            guard range.upperBound < originalText.endIndex else { break }
            remainingRange = range.upperBound..<originalText.endIndex
        }

        guard !ranges.isEmpty else { return }
        matches.append(ClipboardTextMatch(field: field, ranges: ranges))
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

/// A single, coherent publication of the index lifecycle. Consumers must not
/// combine independently published readiness and revision values because that
/// can expose an index from one generation with the status of another.
struct ClipboardSearchIndexState: Sendable {
    let generation: UInt
    let index: ClipboardSearchIndex
    let isReady: Bool

    static let initial = ClipboardSearchIndexState(
        generation: 0,
        index: ClipboardSearchIndex(),
        isReady: false
    )

    func markingPending(generation: UInt) -> ClipboardSearchIndexState {
        ClipboardSearchIndexState(
            generation: generation,
            index: index,
            isReady: false
        )
    }
}

enum ClipboardSearchContentExtractor {
    static func searchableText(
        for item: ClipboardItem,
        loadFileBackedText: () -> String?
    ) -> String {
        switch item.content {
        case .text(let payload):
            return payload.fileName == nil
                ? (payload.inlineText ?? "")
                : (loadFileBackedText() ?? payload.inlineText ?? "")
        case .image(let payload):
            return payload.ocrText ?? ""
        case .color(let payload):
            return payload.originalText
        case .link(let payload):
            return payload.originalText
        case .email(let payload):
            return payload.originalText
        }
    }
}

protocol ClipboardSearchIndexing: Sendable {
    func makeIndex(
        for items: [ClipboardItem],
        assetAccess: any ClipboardAssetAccessing
    ) async -> ClipboardSearchIndex
}

actor ClipboardSearchIndexer: ClipboardSearchIndexing {
    func makeIndex(
        for items: [ClipboardItem],
        assetAccess: any ClipboardAssetAccessing
    ) async -> ClipboardSearchIndex {
        var index = ClipboardSearchIndex()
        index.rebuild(using: items) { item in
            ClipboardSearchContentExtractor.searchableText(for: item) {
                assetAccess.fullText(for: item)
            }
        }
        return index
    }
}
