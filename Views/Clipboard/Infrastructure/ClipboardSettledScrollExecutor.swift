import CoreGraphics
import Foundation

@MainActor
final class ClipboardSettledScrollExecutor {
    enum Command {
        case top
        case bottom
        case offset(CGFloat)
    }

    private var hasFlushedLayoutForSequence = false

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
            flushLayoutIfNeeded(scrollController)
            scrollController.scrollToTop(retryCount: 11)
        case .bottom:
            scrollController.scrollToBottomImmediately()
            flushLayoutIfNeeded(scrollController)
            scrollController.scrollToBottom(retryCount: 11)
        case .offset(let offset):
            scrollController.scrollTo(offset: offset)
            flushLayoutIfNeeded(scrollController)
            scrollController.settleScroll(to: offset, retryCount: 11)
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.hasFlushedLayoutForSequence = false
        }
    }

    private func flushLayoutIfNeeded(_ scrollController: ScrollController) {
        guard !hasFlushedLayoutForSequence else { return }
        hasFlushedLayoutForSequence = true
        scrollController.syncMetricsImmediately()
    }
}
