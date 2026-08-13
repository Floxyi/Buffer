import Foundation

enum ClipboardTextNormalizer {
    static func normalize(_ text: String, mode: ClipboardWhitespaceMode) -> String {
        guard mode.trimsTrailingSpacesAndTabs else { return text }

        var normalized = ""
        normalized.reserveCapacity(text.utf8.count)

        var pendingHorizontalWhitespace = ""

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x20:
                pendingHorizontalWhitespace.unicodeScalars.append(scalar)

            case 0x0A, 0x0D:
                pendingHorizontalWhitespace.removeAll(keepingCapacity: true)
                normalized.unicodeScalars.append(scalar)

            default:
                normalized.append(pendingHorizontalWhitespace)
                pendingHorizontalWhitespace.removeAll(keepingCapacity: true)
                normalized.unicodeScalars.append(scalar)
            }
        }

        return normalized
    }
}

struct PreparedClipboardText: Equatable, Sendable {
    let text: String
    let contentHash: Int

    static func make(
        from text: String,
        whitespaceMode: ClipboardWhitespaceMode
    ) -> PreparedClipboardText? {
        let normalizedText = ClipboardTextNormalizer.normalize(text, mode: whitespaceMode)
        guard !normalizedText.isEmpty else { return nil }

        let hashSource =
            normalizedText.utf8.count > ClipboardCaptureSupport.inlineTextLimit
            ? String(normalizedText.prefix(10_000))
            : normalizedText

        return PreparedClipboardText(
            text: normalizedText,
            contentHash: hashSource.hashValue
        )
    }
}
