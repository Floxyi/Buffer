import CoreGraphics
import Foundation

@MainActor
final class ClipboardKeyboardNavigationCoordinator {
    func cancelAll() {
        // Navigation is applied synchronously; retained for coordinator call-site symmetry.
    }

    func cancelScroll() {
        // Navigation is applied synchronously, so there is no scroll task to cancel.
    }

    func cancelCommit() {
        // Navigation is applied synchronously, so there is no commit task to cancel.
    }

    func scheduleVisibilityScroll(
        to itemID: UUID,
        requestID: UInt,
        currentRequestID: @escaping () -> UInt,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?
    ) {
        guard requestID == currentRequestID() else { return }
        performVisibilityScroll(
            to: itemID,
            scrollController: scrollController,
            resolveMetrics: resolveMetrics
        )
    }

    func scheduleCommit(
        for request: HistoryKeyboardNavigationRequest,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?,
        onComplete: @escaping (HistoryKeyboardNavigationRequest) -> Void
    ) {
        performVisibilityScroll(
            to: request.itemID,
            scrollController: scrollController,
            resolveMetrics: resolveMetrics
        )
        onComplete(request)
    }

    private func performVisibilityScroll(
        to itemID: UUID,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?
    ) {
        guard let metrics = resolveMetrics(itemID) else { return }
        guard abs(metrics.targetOffset - metrics.currentOffset) > 0.5 else { return }

        scrollController.scrollTo(offset: metrics.targetOffset)
        scrollController.syncMetricsImmediately()
    }

}
