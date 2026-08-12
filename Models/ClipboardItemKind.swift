import Foundation

enum ClipboardItemKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case color
    case link
    case email
}

typealias ClipboardItemType = ClipboardItemKind
