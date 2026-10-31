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
            guard let bundleIdentifier = item.normalizedSourceAppBundleIdentifier,
                sourceBundleIdentifiers.contains(bundleIdentifier)
            else {
                return false
            }
        }
        if !kinds.isEmpty, !kinds.contains(item.kind) {
            return false
        }
        if let copiedAt {
            guard item.timestamp >= copiedAt.start, item.timestamp < copiedAt.end else {
                return false
            }
        }
        return true
    }
}

struct ClipboardQuery: Equatable, Sendable {
    var text = ""
    var filters = ClipboardFilters()
    var includesOCRText = true

    var normalizedText: String {
        ClipboardSearchTextNormalizer.normalize(text)
    }

    var isEmpty: Bool {
        normalizedText.isEmpty && filters.isEmpty
    }
}
