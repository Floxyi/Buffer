import Foundation

struct ClipboardQueryPlan: Equatable, Sendable {
    let normalizedPhrase: String
    let normalizedTerms: [String]

    init(_ query: String) {
        normalizedPhrase = ClipboardSearchIndex.normalize(query)
        normalizedTerms = ClipboardTextMatcher.tokens(in: query).map(\.normalizedText)
    }

    var allowsFuzzyMatching: Bool {
        normalizedPhrase.count >= 3 && !normalizedTerms.isEmpty
    }
}

struct ClipboardIndexedToken: Equatable, Sendable {
    let normalizedText: String
    let range: Range<String.Index>
}

struct ClipboardIndexedTextField: Sendable {
    let originalText: String
    let normalizedText: String
    let tokens: [ClipboardIndexedToken]

    init(_ text: String) {
        originalText = text
        normalizedText = ClipboardSearchIndex.normalize(text)
        tokens = ClipboardTextMatcher.tokens(in: text)
    }
}

enum ClipboardTextMatcher {
    struct FuzzyMatch: Sendable {
        let ranges: [Range<String.Index>]
        let totalEditDistance: Int
    }

    static func tokens(in text: String) -> [ClipboardIndexedToken] {
        var result: [ClipboardIndexedToken] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            let normalizedText = ClipboardSearchIndex.normalize(String(text[range]))
            guard !normalizedText.isEmpty else { return }
            result.append(ClipboardIndexedToken(normalizedText: normalizedText, range: range))
        }
        return result
    }

    static func exactRanges(in text: String, normalizedPhrase: String) -> [Range<String.Index>] {
        guard !normalizedPhrase.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var remainingRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: normalizedPhrase,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remainingRange
        ) {
            ranges.append(range)
            guard range.upperBound < text.endIndex else { break }
            remainingRange = range.upperBound..<text.endIndex
        }
        return ranges
    }

    static func fuzzyMatch(
        tokens: [ClipboardIndexedToken],
        resolvedTerms: [[String: Int]]
    ) -> FuzzyMatch? {
        guard !resolvedTerms.isEmpty else { return nil }

        var ranges: [Range<String.Index>] = []
        var totalEditDistance = 0
        var tokenIndex = 0

        for candidates in resolvedTerms {
            var matchedToken: ClipboardIndexedToken?
            var matchedDistance = 0
            while tokenIndex < tokens.count {
                let token = tokens[tokenIndex]
                tokenIndex += 1
                if let distance = candidates[token.normalizedText] {
                    matchedToken = token
                    matchedDistance = distance
                    break
                }
            }

            guard let matchedToken else { return nil }
            ranges.append(matchedToken.range)
            totalEditDistance += matchedDistance
        }

        return FuzzyMatch(ranges: ranges, totalEditDistance: totalEditDistance)
    }

    static func highlightedRanges(
        in text: String,
        queryPlan: ClipboardQueryPlan,
        classification: ClipboardMatchClassification
    ) -> [Range<String.Index>] {
        switch classification {
        case .exact:
            return exactRanges(in: text, normalizedPhrase: queryPlan.normalizedPhrase)
        case .fuzzy:
            let indexedTokens = tokens(in: text)
            let resolvedTerms = queryPlan.normalizedTerms.map { term in
                var candidates: [String: Int] = [:]
                for token in indexedTokens {
                    guard
                        let distance = acceptedEditDistance(
                            from: term,
                            to: token.normalizedText
                        )
                    else { continue }
                    candidates[token.normalizedText] = distance
                }
                return candidates
            }
            return fuzzyMatch(tokens: indexedTokens, resolvedTerms: resolvedTerms)?.ranges ?? []
        }
    }

    static func acceptedEditDistance(from queryTerm: String, to candidate: String) -> Int? {
        if queryTerm.count < 3 || queryTerm.allSatisfy(\.isNumber) {
            return queryTerm == candidate ? 0 : nil
        }

        let maximumDistance = queryTerm.count <= 5 ? 1 : 2
        guard abs(queryTerm.count - candidate.count) <= maximumDistance else { return nil }
        let distance = damerauLevenshteinDistance(queryTerm, candidate)
        return distance <= maximumDistance ? distance : nil
    }

    static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftOffset, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftOffset + 1
            for (rightOffset, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightOffset + 1] = min(
                    previous[rightOffset + 1] + 1,
                    current[rightOffset] + 1,
                    previous[rightOffset] + substitutionCost
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var matrix = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        for leftIndex in 0...left.count {
            matrix[leftIndex][0] = leftIndex
        }
        for rightIndex in 0...right.count {
            matrix[0][rightIndex] = rightIndex
        }

        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                matrix[leftIndex][rightIndex] = min(
                    matrix[leftIndex - 1][rightIndex] + 1,
                    matrix[leftIndex][rightIndex - 1] + 1,
                    matrix[leftIndex - 1][rightIndex - 1] + substitutionCost
                )
                if leftIndex > 1,
                    rightIndex > 1,
                    left[leftIndex - 1] == right[rightIndex - 2],
                    left[leftIndex - 2] == right[rightIndex - 1]
                {
                    matrix[leftIndex][rightIndex] = min(
                        matrix[leftIndex][rightIndex],
                        matrix[leftIndex - 2][rightIndex - 2] + 1
                    )
                }
            }
        }
        return matrix[left.count][right.count]
    }
}

private struct ClipboardVocabularyOccurrence: Hashable, Sendable {
    let itemID: UUID
    let field: ClipboardMatchField
}

private struct ClipboardVocabularyIndex: Sendable {
    private final class Node: @unchecked Sendable {
        let term: String
        var children: [Int: Node] = [:]

        init(term: String) {
            self.term = term
        }
    }

    private let root: Node?
    private let occurrencesByTerm: [String: Set<ClipboardVocabularyOccurrence>]

    init(fieldsByItemID: [UUID: [ClipboardMatchField: ClipboardIndexedTextField]] = [:]) {
        var occurrencesByTerm: [String: Set<ClipboardVocabularyOccurrence>] = [:]
        for (itemID, fields) in fieldsByItemID {
            for (field, indexedField) in fields {
                let occurrence = ClipboardVocabularyOccurrence(itemID: itemID, field: field)
                for term in Set(indexedField.tokens.map(\.normalizedText)) {
                    occurrencesByTerm[term, default: []].insert(occurrence)
                }
            }
        }
        self.occurrencesByTerm = occurrencesByTerm

        var root: Node?
        for term in occurrencesByTerm.keys.sorted() {
            guard let existingRoot = root else {
                root = Node(term: term)
                continue
            }

            var node = existingRoot
            while true {
                let distance = ClipboardTextMatcher.levenshteinDistance(term, node.term)
                if let child = node.children[distance] {
                    node = child
                } else {
                    node.children[distance] = Node(term: term)
                    break
                }
            }
        }
        self.root = root
    }

    func resolvedCandidates(for queryTerm: String) -> [String: Int] {
        if queryTerm.count < 3 || queryTerm.allSatisfy(\.isNumber) {
            return occurrencesByTerm[queryTerm] == nil ? [:] : [queryTerm: 0]
        }

        let maximumDistance = queryTerm.count <= 5 ? 1 : 2
        // A transposition costs two in the tree's Levenshtein metric and one in
        // the final Damerau-style check, so the tree radius must be doubled.
        let treeRadius = maximumDistance * 2
        var nodes = root.map { [$0] } ?? []
        var result: [String: Int] = [:]

        while let node = nodes.popLast() {
            let treeDistance = ClipboardTextMatcher.levenshteinDistance(queryTerm, node.term)
            if let acceptedDistance = ClipboardTextMatcher.acceptedEditDistance(
                from: queryTerm,
                to: node.term
            ) {
                result[node.term] = acceptedDistance
            }

            let lowerBound = max(0, treeDistance - treeRadius)
            let upperBound = treeDistance + treeRadius
            for (distance, child) in node.children
            where distance >= lowerBound && distance <= upperBound {
                nodes.append(child)
            }
        }
        return result
    }

    func occurrences(for terms: some Sequence<String>) -> Set<ClipboardVocabularyOccurrence> {
        terms.reduce(into: Set<ClipboardVocabularyOccurrence>()) { result, term in
            result.formUnion(occurrencesByTerm[term] ?? [])
        }
    }
}

struct ClipboardSearchIndex: Sendable {
    struct Entry: Sendable {
        let contentHash: Int
        let searchableText: String
        let fields: [ClipboardMatchField: ClipboardIndexedTextField]

        var contentText: String { searchableText }
        var sourceApplicationText: String { fields[.sourceApplication]?.originalText ?? "" }
        var ocrText: String { fields[.ocr]?.originalText ?? "" }
    }

    private var cache: [UUID: Entry] = [:]
    private var vocabulary = ClipboardVocabularyIndex()

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

            let contentText: String
            if let cached = cache[item.id], cached.contentHash == item.contentHash {
                contentText = cached.contentText
            } else {
                contentText = loader(item)
            }
            storeEntry(contentText, for: item)
        }

        vocabulary = ClipboardVocabularyIndex(
            fieldsByItemID: cache.mapValues(\.fields)
        )
    }

    func searchableText(for itemID: UUID) -> String {
        cache[itemID]?.contentText ?? ""
    }

    func results(
        for itemIDs: [UUID],
        query: ClipboardQuery
    ) -> [UUID: ClipboardSearchResult] {
        let queryPlan = ClipboardQueryPlan(query.text)
        guard !queryPlan.normalizedPhrase.isEmpty else {
            return Dictionary(
                uniqueKeysWithValues: itemIDs.compactMap { itemID in
                    guard cache[itemID] != nil else { return nil }
                    return (
                        itemID,
                        ClipboardSearchResult(itemID: itemID, score: 0, matches: [])
                    )
                }
            )
        }

        let fields: [ClipboardMatchField] =
            query.includesOCRText
            ? [.content, .sourceApplication, .ocr]
            : [.content, .sourceApplication]
        var results: [UUID: ClipboardSearchResult] = [:]
        var exactItemIDs: Set<UUID> = []

        for itemID in itemIDs {
            guard let entry = cache[itemID] else { continue }
            let matches = fields.compactMap { field -> ClipboardTextMatch? in
                guard let indexedField = entry.fields[field] else { return nil }
                guard indexedField.normalizedText.contains(queryPlan.normalizedPhrase) else {
                    return nil
                }
                let ranges = ClipboardTextMatcher.exactRanges(
                    in: indexedField.originalText,
                    normalizedPhrase: queryPlan.normalizedPhrase
                )
                guard !ranges.isEmpty else { return nil }
                return ClipboardTextMatch(field: field, classification: .exact, ranges: ranges)
            }
            guard !matches.isEmpty else { continue }
            exactItemIDs.insert(itemID)
            results[itemID] = ClipboardSearchResult(
                itemID: itemID,
                score: score(for: matches, fuzzyEditDistance: nil),
                matches: matches
            )
        }

        guard queryPlan.allowsFuzzyMatching else { return results }
        let resolvedTerms = queryPlan.normalizedTerms.map(vocabulary.resolvedCandidates(for:))
        guard resolvedTerms.allSatisfy({ !$0.isEmpty }) else { return results }

        var fuzzyOccurrences: Set<ClipboardVocabularyOccurrence>?
        for candidates in resolvedTerms {
            let occurrences = vocabulary.occurrences(for: candidates.keys)
            fuzzyOccurrences = fuzzyOccurrences.map { $0.intersection(occurrences) } ?? occurrences
        }
        guard let fuzzyOccurrences, !fuzzyOccurrences.isEmpty else { return results }

        for itemID in itemIDs where !exactItemIDs.contains(itemID) {
            guard let entry = cache[itemID] else { continue }
            var matches: [ClipboardTextMatch] = []
            var editDistance = 0
            for field in fields {
                let occurrence = ClipboardVocabularyOccurrence(itemID: itemID, field: field)
                guard fuzzyOccurrences.contains(occurrence),
                    let indexedField = entry.fields[field],
                    let fuzzyMatch = ClipboardTextMatcher.fuzzyMatch(
                        tokens: indexedField.tokens,
                        resolvedTerms: resolvedTerms
                    )
                else {
                    continue
                }
                matches.append(
                    ClipboardTextMatch(
                        field: field,
                        classification: .fuzzy,
                        ranges: fuzzyMatch.ranges
                    )
                )
                editDistance += fuzzyMatch.totalEditDistance
            }
            guard !matches.isEmpty else { continue }
            results[itemID] = ClipboardSearchResult(
                itemID: itemID,
                score: score(for: matches, fuzzyEditDistance: editDistance),
                matches: matches
            )
        }

        return results
    }

    private mutating func storeEntry(_ searchableText: String, for item: ClipboardItem) {
        let fields: [ClipboardMatchField: ClipboardIndexedTextField] = [
            .content: ClipboardIndexedTextField(item.kind == .image ? "" : searchableText),
            .sourceApplication: ClipboardIndexedTextField(item.sourceAppDisplayName ?? ""),
            .ocr: ClipboardIndexedTextField(item.ocrText ?? ""),
        ]
        cache[item.id] = Entry(
            contentHash: item.contentHash,
            searchableText: searchableText,
            fields: fields
        )
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func score(
        for matches: [ClipboardTextMatch],
        fuzzyEditDistance: Int?
    ) -> Double {
        let fieldScore = matches.reduce(0.0) { total, match in
            total + (match.field == .content ? 2 : 1)
        }
        if let fuzzyEditDistance {
            return 100 + (fieldScore * 10) - Double(fuzzyEditDistance)
        }
        return 1_000_000 + fieldScore
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
    private var retainedIndex = ClipboardSearchIndex()

    func makeIndex(
        for items: [ClipboardItem],
        assetAccess: any ClipboardAssetAccessing
    ) async -> ClipboardSearchIndex {
        var index = retainedIndex
        index.rebuild(using: items) { item in
            ClipboardSearchContentExtractor.searchableText(for: item) {
                assetAccess.fullText(for: item)
            }
        }
        retainedIndex = index
        return index
    }
}
