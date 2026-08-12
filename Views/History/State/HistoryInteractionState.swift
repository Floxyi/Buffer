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

struct HistoryKeyboardScrollRequest: Equatable {
    let itemID: UUID
    let targetIndex: Int
    let generation: UInt
    let selectionPublishedAt: ContinuousClock.Instant

    init(
        itemID: UUID,
        targetIndex: Int,
        generation: UInt,
        selectionPublishedAt: ContinuousClock.Instant = .now
    ) {
        self.itemID = itemID
        self.targetIndex = targetIndex
        self.generation = generation
        self.selectionPublishedAt = selectionPublishedAt
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.itemID == rhs.itemID
            && lhs.targetIndex == rhs.targetIndex
            && lhs.generation == rhs.generation
    }
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
