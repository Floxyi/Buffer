import Foundation

struct EmailItemContent: Codable, Equatable, Sendable {
    let address: String
    let originalText: String

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        return components.url
    }
}

enum ClipboardEmailValue {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func parse(_ text: String) -> EmailItemContent? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let detector else {
            return nil
        }

        let fullRange = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: fullRange)

        guard matches.count == 1,
            let match = matches.first,
            match.range == fullRange,
            let detectedURL = match.url,
            detectedURL.scheme?.lowercased() == "mailto",
            let address = URLComponents(
                url: detectedURL,
                resolvingAgainstBaseURL: false
            )?.path,
            !address.isEmpty,
            address == trimmed
        else {
            return nil
        }

        return EmailItemContent(address: address, originalText: text)
    }
}
