import CoreGraphics
import Foundation

@MainActor
final class ClipboardKeyboardNavigationCoordinator {
    nonisolated static let rapidNavigationThreshold = 0.12

    private var scrollTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?
    private var lastNavigationRequestTimestamp = 0.0

    func cancelAll() {
        cancelScroll()
        cancelCommit()
    }

    func cancelScroll() {
        scrollTask?.cancel()
        scrollTask = nil
    }

    func cancelCommit() {
        commitTask?.cancel()
        commitTask = nil
    }

    func scheduleVisibilityScroll(
        to itemID: UUID,
        requestID: UInt,
        currentRequestID: @escaping () -> UInt,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?
    ) {
        cancelScroll()

        scrollTask = Task { @MainActor [weak self] in
            await Task.yield()

            guard let self, !Task.isCancelled else { return }
            guard requestID == currentRequestID() else { return }

            self.performVisibilityScroll(
                to: itemID,
                scrollController: scrollController,
                resolveMetrics: resolveMetrics
            )
            self.scrollTask = nil
        }
    }

    func scheduleCommit(
        for request: HistoryKeyboardNavigationRequest,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?,
        onComplete: @escaping (HistoryKeyboardNavigationRequest) -> Void
    ) {
        cancelCommit()

        let requestTimestamp = Date.timeIntervalSinceReferenceDate
        let shouldPreferImmediateScroll = Self.shouldPreferImmediateScroll(
            currentTimestamp: requestTimestamp,
            previousTimestamp: lastNavigationRequestTimestamp
        )
        lastNavigationRequestTimestamp = requestTimestamp

        commitTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let didAnimateScroll = await self.performAnimatedScrollIfNeeded(
                to: request.itemID,
                preferImmediateScroll: shouldPreferImmediateScroll,
                scrollController: scrollController,
                resolveMetrics: resolveMetrics
            )

            guard !Task.isCancelled else { return }

            if didAnimateScroll {
                try? await Task.sleep(nanoseconds: 30_000_000)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }

            onComplete(request)
            self.commitTask = nil
        }
    }

    nonisolated static func shouldPreferImmediateScroll(
        currentTimestamp: TimeInterval,
        previousTimestamp: TimeInterval,
        rapidNavigationThreshold: TimeInterval = rapidNavigationThreshold
    ) -> Bool {
        currentTimestamp - previousTimestamp < rapidNavigationThreshold
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

    private func performAnimatedScrollIfNeeded(
        to itemID: UUID,
        preferImmediateScroll: Bool,
        scrollController: ScrollController,
        resolveMetrics: @escaping (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?
    ) async -> Bool {
        guard let metrics = resolveMetrics(itemID) else { return false }
        guard abs(metrics.targetOffset - metrics.currentOffset) > 0.5 else { return false }

        if preferImmediateScroll {
            scrollController.scrollTo(offset: metrics.targetOffset)
            scrollController.syncMetricsImmediately()
            return true
        }

        let duration = 0.08
        let frameCount = 6

        for step in 1...frameCount {
            guard !Task.isCancelled else { return false }

            let progress = CGFloat(step) / CGFloat(frameCount)
            let easedProgress = 1 - pow(1 - progress, 3)
            let offset = metrics.currentOffset + (metrics.targetOffset - metrics.currentOffset) * easedProgress

            scrollController.scrollTo(offset: offset)

            if step < frameCount {
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(frameCount)) * 1_000_000_000))
            }
        }

        scrollController.syncMetricsImmediately()
        return true
    }
}
