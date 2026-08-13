import Foundation

struct HistoryViewPresentationState {
    var showsQuickPasteNumbers = false
    var windowOpenToken = 0
    var shouldFocusSearchOnOpen = true
    var searchSelectionToken = 0
    var openListScrollRequest = HistoryOpenListScrollRequest(mode: .scrollToTop)
    var openListScrollRequestToken = 0
    var jumpToHistoryState = HistoryJumpToHistoryState.idle
}
