import SwiftUI

struct ClipboardMatchedText: View {
    let text: String
    let queryPlan: ClipboardQueryPlan?
    let matchClassification: ClipboardMatchClassification?
    var matchEvidence: ClipboardSearchMatchEvidence?
    var searchSnippet: ClipboardSearchSnippet?

    var body: some View {
        highlightedText
    }

    private var highlightedText: Text {
        if let searchSnippet {
            return renderedText(for: searchSnippet.segments)
        }
        let ranges = localHighlightRanges
        guard !ranges.isEmpty else { return Text(text) }

        var segments: [ClipboardSearchSnippetSegment] = []
        segments.reserveCapacity(ranges.count * 2 + 1)
        var cursor = text.startIndex
        for range in ranges {
            if cursor < range.lowerBound {
                segments.append(
                    ClipboardSearchSnippetSegment(
                        text: String(text[cursor..<range.lowerBound]),
                        isHighlighted: false
                    )
                )
            }
            segments.append(
                ClipboardSearchSnippetSegment(
                    text: String(text[range]),
                    isHighlighted: true
                )
            )
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            segments.append(
                ClipboardSearchSnippetSegment(
                    text: String(text[cursor...]),
                    isHighlighted: false
                )
            )
        }
        return renderedText(for: segments)
    }

    private var localHighlightRanges: [Range<String.Index>] {
        let needles: [String]
        if let matchEvidence {
            needles = matchEvidence.terms.compactMap { term in
                if matchEvidence.kind == .prefix {
                    return term.normalizedQueryTerm
                }
                return term.normalizedMatchedTerm
            }
        } else if let queryPlan, matchClassification != nil {
            needles = queryPlan.normalizedTerms
        } else {
            return []
        }

        var ranges: [Range<String.Index>] = []
        for needle in needles where !needle.isEmpty {
            var searchRange = text.startIndex..<text.endIndex
            while let match = text.range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchRange,
                locale: Locale(identifier: "en_US_POSIX")
            ) {
                ranges.append(match)
                guard match.upperBound < text.endIndex else { break }
                searchRange = match.upperBound..<text.endIndex
            }
        }

        let sorted = ranges.sorted { lhs, rhs in
            if lhs.lowerBound == rhs.lowerBound { return lhs.upperBound < rhs.upperBound }
            return lhs.lowerBound < rhs.lowerBound
        }
        var merged: [Range<String.Index>] = []
        for range in sorted {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }
            if range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private func renderedText(
        for segments: [ClipboardSearchSnippetSegment]
    ) -> Text {
        segments.reduce(Text("")) { result, segment in
            guard segment.isHighlighted else { return result + Text(segment.text) }
            return result
                + Text(segment.text)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
        }
    }
}
