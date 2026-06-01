import Foundation

struct LinkItemContent: Codable, Equatable, Sendable {
    let url: URL
    let originalText: String

    var websiteName: String {
        ClipboardLinkValue.websiteName(for: url)
    }

    var displayURL: String {
        url.absoluteString
    }
}
