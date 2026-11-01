import Foundation

struct ClipboardListJumpScrollTaskKey: Equatable {
    let request: HistoryJumpToHistoryRequest?
    let itemCount: Int
    let isShowingFullHistory: Bool
}

struct ClipboardListScrollContext {
    let layoutIndex: ClipboardListLayoutIndex
    let itemExists: (UUID) -> Bool
    let scrollMetrics: () -> SmoothWheelScroller.Metrics
    let onJumpScrollStarted: (HistoryJumpToHistoryRequest) -> Void
    let onJumpScrollCompleted: (HistoryJumpToHistoryRequest, Bool) -> Void
    let log: (String) -> Void
}

enum ClipboardListOpenScrollCommand: Equatable {
    case scrollToTop
    case scrollToItem(UUID)

    init?(request: HistoryOpenListScrollRequest?) {
        guard let request else { return nil }

        switch request.mode {
        case .scrollToTop:
            self = .scrollToTop
        case .scrollToItem(let itemID):
            self = .scrollToItem(itemID)
        }
    }
}

/// The only owner of programmatic list navigation.
///
/// Every target is resolved from the immutable layout index and applied once.
/// Older implementations combined delayed retries, `ScrollViewProxy`, and row
/// measurements; those independent writers could overwrite a newer native
/// user scroll. Fixed-height list geometry makes those retries unnecessary.
@MainActor
final class ClipboardListScrollCoordinator: ObservableObject {
    private enum ItemAlignment {
        case centered
        case visible
    }

    private var scrollRequestID: UInt = 0
    private var lastAppliedOpenScrollRequestToken = -1
    private var activeJumpScrollRequest: HistoryJumpToHistoryRequest?
    private let keyboardNavigationResolver = ClipboardKeyboardNavigationResolver()
    private let keyboardNavigationCoordinator = ClipboardKeyboardNavigationCoordinator()

    func jumpScrollTaskKey(
        request: HistoryJumpToHistoryRequest?,
        itemCount: Int,
        isShowingFullHistory: Bool
    ) -> ClipboardListJumpScrollTaskKey {
        ClipboardListJumpScrollTaskKey(
            request: request,
            itemCount: itemCount,
            isShowingFullHistory: isShowingFullHistory
        )
    }

    func cancelAll() {
        scrollRequestID &+= 1
        activeJumpScrollRequest = nil
        keyboardNavigationCoordinator.invalidateCurrentRequest()
    }

    func syncJumpScrollRequest(_ newRequest: HistoryJumpToHistoryRequest?) {
        if activeJumpScrollRequest != nil,
            activeJumpScrollRequest != newRequest
        {
            activeJumpScrollRequest = nil
        }
    }

    func handleKeyboardScrollRequestChange(
        _ newRequest: HistoryKeyboardScrollRequest?,
        items: [ClipboardItem],
        assetPrewarmer: ClipboardListAssetPrewarmer,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard let newRequest else {
            keyboardNavigationCoordinator.invalidateCurrentRequest()
            return
        }

        guard items[safe: newRequest.targetIndex]?.id == newRequest.itemID else { return }

        let result = keyboardNavigationCoordinator.scrollSelectedItemIntoView(
            request: newRequest,
            targetFrameExists: context.layoutIndex.frame(for: newRequest.itemID) != nil,
            scrollController: scrollController,
            resolveMetrics: { [weak self] itemID in
                self?.keyboardNavigationMetrics(for: itemID, context: context)
            }
        )
        guard result.didApplyViewportOperation else { return }

        BufferPerformanceDiagnostics.recordElapsed(
            since: newRequest.selectionPublishedAt,
            for: .keyboardScroll
        )
        assetPrewarmer.prewarmAssetsForKeyboardNavigation(
            request: newRequest,
            items: items
        )
    }

    func waitAndStartJumpScrollIfReady(
        _ request: HistoryJumpToHistoryRequest,
        currentJumpScrollRequest: @escaping () -> HistoryJumpToHistoryRequest?,
        isShowingFullHistory: @escaping () -> Bool,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) async {
        let token = BufferPerformanceDiagnostics.begin(.jumpScroll)
        defer { BufferPerformanceDiagnostics.end(token) }
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        for attempt in 0..<12 {
            guard requestID == scrollRequestID,
                currentJumpScrollRequest() == request
            else { return }

            if attempt == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .milliseconds(70))
            }
            guard !Task.isCancelled, requestID == scrollRequestID else { return }

            scrollController.syncMetricsImmediately()

            let targetExists = context.itemExists(request.itemID)
            let fullHistoryReady = isShowingFullHistory()
            context.log(
                "Jump list check item=\(request.itemID.uuidString) generation=\(request.generation) "
                    + "attempt=\(attempt) fullHistoryReady=\(fullHistoryReady) targetExists=\(targetExists)"
            )

            guard fullHistoryReady, targetExists else { continue }

            activeJumpScrollRequest = request
            context.onJumpScrollStarted(request)
            let succeeded = scrollToItem(
                request.itemID,
                alignment: .centered,
                scrollController: scrollController,
                context: context
            )
            finishJumpScroll(request, succeeded: succeeded, context: context)
            return
        }

        context.onJumpScrollCompleted(request, false)
    }

    func selectFirstItemAndScrollToTop(
        preferredTopItemID: UUID?,
        firstItemID: UUID?,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard let preferredTopItemID else {
            scrollToTop(scrollController: scrollController)
            return
        }

        if firstItemID == preferredTopItemID {
            scrollToTop(scrollController: scrollController)
        } else {
            _ = scrollToItem(
                preferredTopItemID,
                alignment: .visible,
                scrollController: scrollController,
                context: context
            )
        }
    }

    func applyOpenScrollRequestIfNeeded(
        request: HistoryOpenListScrollRequest?,
        requestToken: Int,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard requestToken != lastAppliedOpenScrollRequestToken else { return }
        lastAppliedOpenScrollRequestToken = requestToken

        guard let command = ClipboardListOpenScrollCommand(request: request) else { return }

        switch command {
        case .scrollToTop:
            scrollToTop(scrollController: scrollController)
        case .scrollToItem(let itemID):
            _ = scrollToItem(
                itemID,
                alignment: .centered,
                scrollController: scrollController,
                context: context
            )
        }
    }

    func restoreScrollOffsetForReopen(
        _ offset: CGFloat,
        scrollController: ScrollController
    ) {
        applyProgrammaticScroll(to: offset, scrollController: scrollController)
    }

    private func scrollToItem(
        _ itemID: UUID,
        alignment: ItemAlignment,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) -> Bool {
        guard let frame = context.layoutIndex.frame(for: itemID) else { return false }

        scrollController.syncMetricsImmediately()

        let metrics = scrollController.currentMetrics()
        let viewportHeight = max(1, metrics.viewportHeight)
        let maxOffset = max(0, context.layoutIndex.contentHeight - viewportHeight)
        let targetOffset: CGFloat?

        switch alignment {
        case .centered:
            targetOffset = (frame.midY - viewportHeight / 2).clamped(to: 0...maxOffset)
        case .visible:
            targetOffset =
                keyboardNavigationResolver.resolveMetrics(
                    for: itemID,
                    layoutIndex: context.layoutIndex,
                    scrollMetrics: metrics
                )?.targetOffset
        }

        if let targetOffset {
            scrollController.scrollTo(offset: targetOffset)
            scrollController.syncMetricsImmediately()
        }
        return true
    }

    private func finishJumpScroll(
        _ request: HistoryJumpToHistoryRequest,
        succeeded: Bool,
        context: ClipboardListScrollContext
    ) {
        guard activeJumpScrollRequest == request else { return }
        activeJumpScrollRequest = nil
        context.onJumpScrollCompleted(request, succeeded)
    }

    private func keyboardNavigationMetrics(
        for itemID: UUID,
        context: ClipboardListScrollContext
    ) -> (currentOffset: CGFloat, targetOffset: CGFloat)? {
        keyboardNavigationResolver.resolveMetrics(
            for: itemID,
            layoutIndex: context.layoutIndex,
            scrollMetrics: context.scrollMetrics()
        ).map { metrics in
            (currentOffset: metrics.currentOffset, targetOffset: metrics.targetOffset)
        }
    }

    private func scrollToTop(scrollController: ScrollController) {
        applyProgrammaticScroll(to: 0, scrollController: scrollController)
    }

    private func applyProgrammaticScroll(
        to offset: CGFloat,
        scrollController: ScrollController
    ) {
        scrollRequestID &+= 1
        scrollController.scrollTo(offset: offset)
        scrollController.syncMetricsImmediately()
    }
}
