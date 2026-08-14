import Foundation

struct ClipboardFilters: Equatable, Sendable {
    var requiresBookmark = false
    var sourceBundleIdentifiers: Set<String> = []
    var kinds: Set<ClipboardItemKind> = []
    var copiedAt: DateInterval?

    var isEmpty: Bool {
        !requiresBookmark
            && sourceBundleIdentifiers.isEmpty
            && kinds.isEmpty
            && copiedAt == nil
    }

    func matches(_ item: ClipboardItem) -> Bool {
        if requiresBookmark, !item.isBookmarked {
            return false
        }
        if !sourceBundleIdentifiers.isEmpty {
            guard let bundleIdentifier = item.sourceAppBundleIdentifier,
                sourceBundleIdentifiers.contains(bundleIdentifier)
            else {
                return false
            }
        }
        if !kinds.isEmpty, !kinds.contains(item.kind) {
            return false
        }
        if let copiedAt, !copiedAt.contains(item.timestamp) {
            return false
        }
        return true
    }
}

struct ClipboardQuery: Equatable, Sendable {
    var text = ""
    var filters = ClipboardFilters()
    var includesOCRText = true

    var normalizedText: String {
        ClipboardSearchIndex.normalize(text)
    }

    var isEmpty: Bool {
        normalizedText.isEmpty && filters.isEmpty
    }
}

enum ClipboardMatchField: Hashable, Sendable {
    case content
    case sourceApplication
    case ocr
}

enum ClipboardMatchClassification: Equatable, Sendable {
    case exact
    case fuzzy
}

struct ClipboardTextMatch: Equatable, Sendable {
    let field: ClipboardMatchField
    let classification: ClipboardMatchClassification
    let ranges: [Range<String.Index>]
}

struct ClipboardSearchResult: Equatable, Sendable, Identifiable {
    let itemID: UUID
    let score: Double
    let matches: [ClipboardTextMatch]

    var id: UUID { itemID }
}
