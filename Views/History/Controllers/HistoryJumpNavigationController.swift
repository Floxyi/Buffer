import Foundation

struct HistoryNavigationState {
    var jumpToHistoryState = HistoryJumpToHistoryState.idle
    var jumpToHistoryGenerationCounter: UInt = 0
    var jumpToHistoryFailureCount = 0
    var keyboardScrollRequest: HistoryKeyboardScrollRequest?
    var keyboardScrollGenerationCounter: UInt = 0
}

struct HistoryJumpNavigationController {
    private let maxJumpToHistoryRetryCount = 2

    func beginJump(to itemID: UUID, state: HistoryNavigationState) -> HistoryNavigationState {
        var nextState = state
        nextState.jumpToHistoryGenerationCounter &+= 1
        nextState.jumpToHistoryFailureCount = 0
        nextState.jumpToHistoryState = .pending(
            HistoryJumpToHistoryRequest(
                itemID: itemID,
                generation: nextState.jumpToHistoryGenerationCounter
            )
        )
        return nextState
    }

    func markJumpScrollStarted(
        _ request: HistoryJumpToHistoryRequest,
        state: HistoryNavigationState
    ) -> HistoryNavigationState {
        guard state.jumpToHistoryState.request == request else {
            return state
        }

        var nextState = state
        nextState.jumpToHistoryState = .scrolling(request)
        return nextState
    }

    func completeJumpScroll(
        _ request: HistoryJumpToHistoryRequest,
        succeeded: Bool,
        state: HistoryNavigationState
    ) -> HistoryNavigationState {
        guard state.jumpToHistoryState.request == request else {
            return state
        }

        var nextState = state

        if succeeded {
            nextState.jumpToHistoryState = .idle
            nextState.jumpToHistoryFailureCount = 0
            return nextState
        }

        switch nextState.jumpToHistoryState {
        case .idle:
            return nextState
        case .scrolling:
            nextState.jumpToHistoryState = .idle
            nextState.jumpToHistoryFailureCount = 0
            return nextState
        case .pending:
            nextState.jumpToHistoryFailureCount += 1

            guard nextState.jumpToHistoryFailureCount <= maxJumpToHistoryRetryCount else {
                nextState.jumpToHistoryState = .idle
                nextState.jumpToHistoryFailureCount = 0
                return nextState
            }

            nextState.jumpToHistoryGenerationCounter &+= 1
            nextState.jumpToHistoryState = .pending(
                HistoryJumpToHistoryRequest(
                    itemID: request.itemID,
                    generation: nextState.jumpToHistoryGenerationCounter
                )
            )
            return nextState
        }
    }

    func makeKeyboardScrollRequest(
        itemID: UUID,
        targetIndex: Int,
        state: HistoryNavigationState
    ) -> HistoryNavigationState {
        var nextState = state
        nextState.keyboardScrollGenerationCounter &+= 1
        nextState.keyboardScrollRequest = HistoryKeyboardScrollRequest(
            itemID: itemID,
            targetIndex: targetIndex,
            generation: nextState.keyboardScrollGenerationCounter
        )
        return nextState
    }

    func clearKeyboardScrollRequest(
        state: HistoryNavigationState
    ) -> HistoryNavigationState {
        var nextState = state
        nextState.keyboardScrollRequest = nil
        return nextState
    }
}
