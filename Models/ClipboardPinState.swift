import Foundation

enum ClipboardPinState: Sendable {
    case pinned
    case unpinned

    var isPinned: Bool {
        switch self {
        case .pinned:
            return true
        case .unpinned:
            return false
        }
    }
}
