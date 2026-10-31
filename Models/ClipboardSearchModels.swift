import Foundation

enum ClipboardMatchField: Hashable, Sendable {
    case content
    case sourceApplication
    case ocr
}

enum ClipboardMatchClassification: Equatable, Sendable {
    case exact
    case fuzzy
}

struct ClipboardSearchSnippetSegment: Equatable, Sendable {
    let text: String
    let isHighlighted: Bool
}

struct ClipboardSearchSnippet: Equatable, Sendable {
    let sessionID: ClipboardSearchSessionID
    let field: ClipboardMatchField
    let segments: [ClipboardSearchSnippetSegment]

    var text: String {
        segments.map(\.text).joined()
    }
}

enum ClipboardSearchRelevanceMethod: Int, Equatable, Sendable {
    case ftsBM25
    case boundedIDFLengthV1
}

struct ClipboardSearchRelevance: Equatable, Sendable {
    let score: Double
    let method: ClipboardSearchRelevanceMethod
}

enum ClipboardSearchMatchTier: Int, Comparable, Sendable {
    case fuzzy = 1
    case substring = 2
    case prefix = 3
    case exactToken = 4
    case literalPhrase = 5

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ClipboardSearchFieldPriority: Int, Comparable, Sendable {
    case sourceApplication = 1
    case ocr = 2
    case content = 3

    init(_ field: ClipboardMatchField) {
        switch field {
        case .sourceApplication: self = .sourceApplication
        case .ocr: self = .ocr
        case .content: self = .content
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ClipboardSearchRank: Equatable, Sendable {
    let tier: ClipboardSearchMatchTier
    let fieldPriority: ClipboardSearchFieldPriority
    let editDistance: Int
    let relevance: ClipboardSearchRelevance
    let copiedAt: TimeInterval
}

struct ClipboardSearchCommittedState: Equatable, Sendable {
    static let initial = ClipboardSearchCommittedState(
        indexGeneration: 0,
        historyRevision: 0,
        vocabularyGeneration: 0,
        appliedVocabularySequence: 0
    )

    let indexGeneration: UInt64
    let historyRevision: UInt64
    let vocabularyGeneration: UInt64
    let appliedVocabularySequence: UInt64
}

struct ClipboardSearchRequest: Sendable {
    let queryGeneration: UInt64
    let historyRevision: UInt64
    let query: ClipboardQuery
}

struct ClipboardSearchSessionID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum ClipboardSearchMatchKind: Int, Sendable, Equatable {
    case literalPhrase
    case exactToken
    case prefix
    case substring
    case fuzzyCorrection

    var classification: ClipboardMatchClassification {
        self == .fuzzyCorrection ? .fuzzy : .exact
    }
}

enum ClipboardSearchResultRegion: Sendable, Equatable {
    case strict
    case similar
}

struct ClipboardSearchTermEvidence: Sendable, Equatable {
    let queryTermIndex: Int
    let normalizedQueryTerm: String
    let normalizedMatchedTerm: String
    let editDistance: Int
    let weightedEditCost: Double
}

struct ClipboardSearchMatchEvidence: Sendable, Equatable {
    let sessionID: ClipboardSearchSessionID
    let field: ClipboardMatchField
    let kind: ClipboardSearchMatchKind
    let terms: [ClipboardSearchTermEvidence]
    let correctionQuality: Double?
}

struct ClipboardSearchHit: Sendable, Identifiable, Equatable {
    let itemID: UUID
    let region: ClipboardSearchResultRegion
    let rank: ClipboardSearchRank
    let evidence: ClipboardSearchMatchEvidence
    var snippet: ClipboardSearchSnippet?

    var id: UUID { itemID }
}

struct ClipboardSearchSession: Equatable, Sendable {
    let id: ClipboardSearchSessionID
    let queryGeneration: UInt64
    let committedState: ClipboardSearchCommittedState
}

struct ClipboardSearchCoverage: Equatable, Sendable {
    let corpusIsComplete: Bool
    let similarResultsAreComplete: Bool
}

struct ClipboardSearchResponse: Sendable {
    let session: ClipboardSearchSession
    let coverage: ClipboardSearchCoverage
    let hits: [ClipboardSearchHit]

    var totalCount: Int { hits.count }
}

struct ClipboardSearchSnippetRequest: Sendable {
    let session: ClipboardSearchSession
    let itemIDs: [UUID]
}

struct ClipboardSearchSnippetBatch: Sendable {
    let session: ClipboardSearchSession
    let snippetsByItemID: [UUID: ClipboardSearchSnippet]
}
