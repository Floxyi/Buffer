import SwiftUI

struct ClipboardMatchedText: View {
    let text: String
    let queryPlan: ClipboardQueryPlan?
    let matchClassification: ClipboardMatchClassification?

    var body: some View {
        highlightedText
    }

    private var highlightedText: Text {
        guard let queryPlan, let matchClassification else {
            return Text(text)
        }

        let ranges = ClipboardTextMatcher.highlightedRanges(
            in: text,
            queryPlan: queryPlan,
            classification: matchClassification
        )
        guard !ranges.isEmpty else { return Text(text) }

        var result = Text("")
        var cursor = text.startIndex
        for range in ranges {
            result = result + Text(String(text[cursor..<range.lowerBound]))
            result =
                result
                + Text(String(text[range]))
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            cursor = range.upperBound
        }
        return result + Text(String(text[cursor...]))
    }
}
