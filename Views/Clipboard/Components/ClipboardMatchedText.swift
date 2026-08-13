import SwiftUI

struct ClipboardMatchedText: View {
    let text: String
    let query: String?

    var body: some View {
        highlightedText
    }

    private var highlightedText: Text {
        guard let query, !query.isEmpty else {
            return Text(text)
        }

        var result = Text("")
        var cursor = text.startIndex
        var foundMatch = false

        while cursor < text.endIndex,
            let match = text.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: cursor..<text.endIndex
            )
        {
            foundMatch = true
            result = result + Text(String(text[cursor..<match.lowerBound]))
            result =
                result
                + Text(String(text[match]))
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
            cursor = match.upperBound
        }

        guard foundMatch else { return Text(text) }
        return result + Text(String(text[cursor...]))
    }
}
