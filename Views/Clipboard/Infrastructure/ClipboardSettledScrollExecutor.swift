import CoreGraphics
import Foundation

@MainActor
final class ClipboardSettledScrollExecutor {
    enum Command {
        case top
        case bottom
        case offset(CGFloat)
    }

    func execute(
        _ command: Command,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator?,
        keyboardNavigationCoordinator: ClipboardKeyboardNavigationCoordinator,
        scrollController: ScrollController
    ) {
        measuredScrollCoordinator?.cancel()
        keyboardNavigationCoordinator.cancelScroll()

        switch command {
        case .top:
            scrollController.scrollToTopImmediately()
            scrollController.syncMetricsImmediately()
            scrollController.scrollToTop(retryCount: 11)
        case .bottom:
            scrollController.scrollToBottomImmediately()
            scrollController.syncMetricsImmediately()
            scrollController.scrollToBottom(retryCount: 11)
        case .offset(let offset):
            scrollController.scrollTo(offset: offset)
            scrollController.syncMetricsImmediately()
            scrollController.settleScroll(to: offset, retryCount: 11)
        }
    }
}
