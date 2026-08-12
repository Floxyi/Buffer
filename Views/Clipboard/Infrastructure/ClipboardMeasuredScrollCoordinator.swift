import Foundation
import SwiftUI

struct ClipboardMeasuredScrollRequest: Equatable {
    enum Alignment: Equatable {
        case centered
        case visible
    }

    let itemID: UUID
    let alignment: Alignment
    let requestID: UInt
}

struct ClipboardMeasuredScrollContext {
    let currentRequestID: () -> UInt
    let itemExists: (UUID) -> Bool
    let displayRows: () -> [ClipboardListStructure.DisplayRow]
    let layoutIndex: () -> ClipboardListLayoutIndex
    let log: (String) -> Void
}

@MainActor
final class ClipboardMeasuredScrollCoordinator: ObservableObject {
    @Published private(set) var pendingRequest: ClipboardMeasuredScrollRequest?
    @Published private(set) var measuredTargetFrame: CGRect?

    var pendingItemID: UUID? {
        pendingRequest?.itemID
    }

    private var completion: ((Bool) -> Void)?
    private var scrollTask: Task<Void, Never>?

    func schedule(
        _ request: ClipboardMeasuredScrollRequest,
        using scrollProxy: ScrollViewProxy,
        scrollController: ScrollController,
        context: ClipboardMeasuredScrollContext,
        completion: ((Bool) -> Void)? = nil
    ) {
        cancel()

        pendingRequest = request
        measuredTargetFrame = nil
        self.completion = completion

        scrollTask = Task { @MainActor in
            let attemptCount = ClipboardMeasuredScrollGeometry.attemptCount(for: request.alignment)
            let anchor = ClipboardMeasuredScrollGeometry.anchor(for: request.alignment)

            for attempt in 0..<attemptCount {
                guard !Task.isCancelled else {
                    return
                }

                guard request.requestID == context.currentRequestID() else {
                    finish(requestID: request.requestID, succeeded: false)
                    return
                }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                guard !Task.isCancelled else {
                    return
                }

                guard context.itemExists(request.itemID) else {
                    continue
                }

                if attempt == 0 {
                    scrollController.syncMetricsImmediately()
                } else {
                    scrollController.syncMetrics()
                }

                if request.alignment == .centered, attempt < 3 {
                    scrollToEstimatedPosition(
                        for: request.itemID,
                        alignment: request.alignment,
                        scrollController: scrollController,
                        context: context
                    )
                }

                if ClipboardMeasuredScrollGeometry.shouldUseProxyScroll(
                    alignment: request.alignment,
                    measuredTargetFrame: measuredTargetFrame,
                    attempt: attempt
                ) {
                    withAnimation(nil) {
                        scrollProxy.scrollTo(
                            clipboardListScrollID(for: request.itemID),
                            anchor: anchor
                        )
                    }
                }

                await Task.yield()
                try? await Task.sleep(nanoseconds: 14_000_000)

                guard !Task.isCancelled else {
                    return
                }

                if performExactMeasuredScroll(
                    request: request,
                    scrollController: scrollController
                ) {
                    context.log("Measured scroll succeeded for \(request.itemID.uuidString)")
                    finish(requestID: request.requestID, succeeded: true)
                    return
                }
            }

            context.log("Measured scroll failed for \(request.itemID.uuidString)")
            finish(requestID: request.requestID, succeeded: false)
        }
    }

    func handleMeasuredTargetFrameChange(
        _ frame: CGRect?,
        scrollController: ScrollController,
        context: ClipboardMeasuredScrollContext
    ) {
        measuredTargetFrame = frame

        guard let pendingRequest else {
            return
        }

        guard pendingRequest.requestID == context.currentRequestID() else {
            return
        }

        if performExactMeasuredScroll(
            request: pendingRequest,
            scrollController: scrollController
        ) {
            finish(requestID: pendingRequest.requestID, succeeded: true)
        }
    }

    func cancel() {
        scrollTask?.cancel()
        scrollTask = nil

        pendingRequest = nil
        measuredTargetFrame = nil

        let currentCompletion = completion
        completion = nil
        currentCompletion?(false)
    }

    private func finish(requestID: UInt, succeeded: Bool) {
        guard pendingRequest?.requestID == requestID else {
            return
        }

        pendingRequest = nil
        measuredTargetFrame = nil
        scrollTask = nil

        let currentCompletion = completion
        completion = nil
        currentCompletion?(succeeded)
    }

    private func scrollToEstimatedPosition(
        for itemID: UUID,
        alignment: ClipboardMeasuredScrollRequest.Alignment,
        scrollController: ScrollController,
        context: ClipboardMeasuredScrollContext
    ) {
        guard
            let estimatedMidY = context.layoutIndex().midY(for: itemID)
        else {
            return
        }

        let viewportHeight = max(1, scrollController.viewportHeight)
        let targetOffset = ClipboardMeasuredScrollGeometry.estimatedTargetOffset(
            estimatedMidY: estimatedMidY,
            viewportHeight: viewportHeight,
            alignment: alignment
        )

        context.log(
            "Estimated jump scroll item=\(itemID.uuidString) targetOffset=\(targetOffset)"
        )

        scrollController.scrollTo(offset: targetOffset)
        scrollController.syncMetrics()
    }

    @discardableResult
    private func performExactMeasuredScroll(
        request: ClipboardMeasuredScrollRequest,
        scrollController: ScrollController
    ) -> Bool {
        guard pendingRequest?.itemID == request.itemID,
            let measuredTargetFrame
        else {
            return false
        }

        scrollController.syncMetrics()

        let viewportHeight = max(1, scrollController.viewportHeight)
        let target = ClipboardMeasuredScrollGeometry.exactTarget(
            measuredTargetFrame: measuredTargetFrame,
            viewportHeight: viewportHeight,
            currentOffset: scrollController.scrollOffset,
            contentHeight: scrollController.contentHeight,
            alignment: request.alignment
        )

        switch target {
        case .alreadyVisible:
            return true
        case .scrollTo(let clampedTargetOffset):
            guard abs(scrollController.scrollOffset - clampedTargetOffset) > 1 else {
                return true
            }

            scrollController.scrollTo(offset: clampedTargetOffset)
            scrollController.syncMetrics()

            return abs(scrollController.scrollOffset - clampedTargetOffset) <= 2
        }
    }
}
