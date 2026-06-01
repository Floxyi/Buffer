import Foundation

enum ClipboardItemKind: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case color
    case link
}

typealias ClipboardItemType = ClipboardItemKind
