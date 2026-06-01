import Foundation

struct HistoryOpenListScrollRequest: Equatable {
    enum Mode: Equatable {
        case scrollToTop
        case scrollToItem(UUID)
    }

    let mode: Mode
}

struct HistoryJumpToHistoryRequest: Equatable {
    let itemID: UUID
    let generation: UInt
}

struct HistoryKeyboardNavigationRequest: Equatable {
    let itemID: UUID
    let targetIndex: Int
    let generation: UInt
}

enum HistoryJumpToHistoryState: Equatable {
    case idle
    case pending(HistoryJumpToHistoryRequest)
    case scrolling(HistoryJumpToHistoryRequest)

    var request: HistoryJumpToHistoryRequest? {
        switch self {
        case .idle:
            return nil
        case .pending(let request), .scrolling(let request):
            return request
        }
    }

    var itemID: UUID? {
        request?.itemID
    }
}
