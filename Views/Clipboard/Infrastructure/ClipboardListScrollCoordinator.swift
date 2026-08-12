import Foundation
import SwiftUI

struct ClipboardListJumpScrollTaskKey: Equatable {
    let request: HistoryJumpToHistoryRequest?
    let itemCount: Int
    let isShowingFullHistory: Bool
}

struct ClipboardListScrollContext {
    let items: [ClipboardItem]
    let displayRows: [ClipboardListStructure.DisplayRow]
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
        guard let request else {
            return nil
        }

        switch request.mode {
        case .scrollToTop:
            self = .scrollToTop
        case .scrollToItem(let itemID):
            self = .scrollToItem(itemID)
        }
    }
}

@MainActor
final class ClipboardListScrollCoordinator: ObservableObject {
    @Published private(set) var isAwaitingInitialOpenScroll = false

    private var scrollRequestID: UInt = 0
    private var lastAppliedOpenScrollRequestToken = -1
    private var activeJumpScrollRequest: HistoryJumpToHistoryRequest?
    private let keyboardNavigationResolver = ClipboardKeyboardNavigationResolver()
    private let keyboardNavigationCoordinator = ClipboardKeyboardNavigationCoordinator()
    private let settledScrollExecutor = ClipboardSettledScrollExecutor()

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

    func currentRequestID() -> UInt {
        scrollRequestID
    }

    func cancelAll(measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator) {
        measuredScrollCoordinator.cancel()
    }

    func syncJumpScrollRequest(_ newRequest: HistoryJumpToHistoryRequest?) {
        if activeJumpScrollRequest != nil,
            activeJumpScrollRequest != newRequest
        {
            activeJumpScrollRequest = nil
        }
    }

    func handleSelectionNavigation(
        to itemID: UUID,
        using scrollProxy: ScrollViewProxy,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        scheduleMeasuredScroll(
            request: ClipboardMeasuredScrollRequest(
                itemID: itemID,
                alignment: .centered,
                requestID: nextRequestID()
            ),
            using: scrollProxy,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController,
            context: context
        )
    }

    func handleSelectedIndexChange(
        selectedIndex: Int,
        itemCount: Int,
        itemID: UUID?,
        scrollTrigger: inout Bool,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard scrollTrigger else { return }

        scrollTrigger = false

        if selectedIndex == 0 {
            scheduleSettledScroll(
                .top,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController
            )
        } else if selectedIndex == itemCount - 1 {
            scheduleSettledScroll(
                .bottom,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController
            )
        } else if let itemID {
            scheduleKeyboardNavigationScroll(
                to: itemID,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: context
            )
        }
    }

    func handleKeyboardScrollRequestChange(
        _ newRequest: HistoryKeyboardScrollRequest?,
        items: [ClipboardItem],
        store: ClipboardStore,
        settings: SettingsManager,
        assetPrewarmer: ClipboardListAssetPrewarmer,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard let newRequest else {
            keyboardNavigationCoordinator.invalidateCurrentRequest()
            return
        }

        guard items[safe: newRequest.targetIndex]?.id == newRequest.itemID else {
            return
        }

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
            items: items,
            store: store,
            settings: settings
        )
    }

    func handleMeasuredTargetFrameChange(
        _ frame: CGRect?,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        measuredScrollCoordinator.handleMeasuredTargetFrameChange(
            frame,
            scrollController: scrollController,
            context: measuredScrollContext(for: context)
        )
    }

    func waitAndStartJumpScrollIfReady(
        _ request: HistoryJumpToHistoryRequest,
        currentJumpScrollRequest: @escaping () -> HistoryJumpToHistoryRequest?,
        isShowingFullHistory: @escaping () -> Bool,
        using scrollProxy: ScrollViewProxy,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext,
        rebuildListCache: @escaping () -> Void
    ) async {
        let token = BufferPerformanceDiagnostics.begin(.jumpScroll)
        defer { BufferPerformanceDiagnostics.end(token) }

        for attempt in 0..<12 {
            guard currentJumpScrollRequest() == request else {
                return
            }

            if attempt == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: 70_000_000)
            }

            guard !Task.isCancelled else {
                return
            }

            rebuildListCache()
            if attempt == 0 {
                scrollController.syncMetricsImmediately()
            } else {
                scrollController.syncMetrics()
            }

            let targetExists = context.itemExists(request.itemID)
            let fullHistoryReady = isShowingFullHistory()

            context.log(
                "Jump list check item=\(request.itemID.uuidString) generation=\(request.generation) attempt=\(attempt) fullHistoryReady=\(fullHistoryReady) targetExists=\(targetExists)"
            )

            guard fullHistoryReady else {
                continue
            }

            guard targetExists else {
                continue
            }

            activeJumpScrollRequest = request
            context.onJumpScrollStarted(request)

            scheduleMeasuredScroll(
                request: ClipboardMeasuredScrollRequest(
                    itemID: request.itemID,
                    alignment: .centered,
                    requestID: nextRequestID()
                ),
                using: scrollProxy,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: context,
                completion: { [weak self] succeeded in
                    self?.finishJumpScroll(request, succeeded: succeeded, context: context)
                }
            )

            return
        }

        context.onJumpScrollCompleted(request, false)
    }

    func selectFirstItemAndScrollToTop(
        preferredTopItemID: UUID?,
        firstItemID: UUID?,
        using scrollProxy: ScrollViewProxy,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard let preferredTopItemID else {
            scheduleOpenScrollToTop(scrollController: scrollController)
            return
        }

        if firstItemID == preferredTopItemID {
            scheduleOpenScrollToTop(scrollController: scrollController)
        } else {
            scheduleMeasuredScroll(
                request: ClipboardMeasuredScrollRequest(
                    itemID: preferredTopItemID,
                    alignment: .visible,
                    requestID: nextRequestID()
                ),
                using: scrollProxy,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: context
            )
        }
    }

    func applyOpenScrollRequestIfNeeded(
        request: HistoryOpenListScrollRequest?,
        requestToken: Int,
        using scrollProxy: ScrollViewProxy,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        guard requestToken != lastAppliedOpenScrollRequestToken else {
            return
        }

        lastAppliedOpenScrollRequestToken = requestToken

        guard let command = ClipboardListOpenScrollCommand(request: request) else {
            return
        }

        isAwaitingInitialOpenScroll = Self.shouldHideDuringInitialOpenScroll(
            for: command,
            currentScrollOffset: scrollController.scrollOffset
        )

        switch command {
        case .scrollToTop:
            scheduleOpenScrollToTop(scrollController: scrollController)

        case .scrollToItem(let itemID):
            scheduleMeasuredScroll(
                request: ClipboardMeasuredScrollRequest(
                    itemID: itemID,
                    alignment: .centered,
                    requestID: nextRequestID()
                ),
                using: scrollProxy,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: context
            )
        }
    }

    func restoreScrollOffsetForReopen(
        _ offset: CGFloat,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController
    ) {
        isAwaitingInitialOpenScroll = offset > 1
        scheduleSettledScroll(
            .offset(offset),
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController
        )
        isAwaitingInitialOpenScroll = false
    }

    nonisolated static func shouldHideDuringInitialOpenScroll(
        for command: ClipboardListOpenScrollCommand?,
        currentScrollOffset: CGFloat
    ) -> Bool {
        guard let command else {
            return false
        }

        switch command {
        case .scrollToTop:
            return currentScrollOffset > 1
        case .scrollToItem:
            return false
        }
    }

    private func scheduleMeasuredScroll(
        request: ClipboardMeasuredScrollRequest,
        using scrollProxy: ScrollViewProxy,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext,
        completion: ((Bool) -> Void)? = nil
    ) {
        measuredScrollCoordinator.schedule(
            request,
            using: scrollProxy,
            scrollController: scrollController,
            context: measuredScrollContext(for: context),
            completion: completion
        )
    }

    private func measuredScrollContext(for context: ClipboardListScrollContext) -> ClipboardMeasuredScrollContext {
        ClipboardMeasuredScrollContext(
            currentRequestID: { [weak self] in
                self?.scrollRequestID ?? 0
            },
            itemExists: context.itemExists,
            displayRows: { context.displayRows },
            layoutIndex: { context.layoutIndex },
            log: context.log
        )
    }

    private func finishJumpScroll(
        _ request: HistoryJumpToHistoryRequest,
        succeeded: Bool,
        context: ClipboardListScrollContext
    ) {
        guard activeJumpScrollRequest == request else {
            return
        }

        activeJumpScrollRequest = nil
        context.onJumpScrollCompleted(request, succeeded)
    }

    private func scheduleKeyboardNavigationScroll(
        to itemID: UUID,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator,
        scrollController: ScrollController,
        context: ClipboardListScrollContext
    ) {
        let requestID = nextRequestID()

        measuredScrollCoordinator.cancel()
        guard requestID == scrollRequestID,
            let metrics = keyboardNavigationMetrics(for: itemID, context: context),
            abs(metrics.targetOffset - metrics.currentOffset) > 0.5
        else {
            return
        }
        scrollController.scrollTo(offset: metrics.targetOffset)
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

    private func scheduleOpenScrollToTop(scrollController: ScrollController) {
        scrollController.scrollToTopImmediately()
        scrollController.syncMetrics()
        isAwaitingInitialOpenScroll = false
        scheduleSettledScroll(.top, measuredScrollCoordinator: nil, scrollController: scrollController)
    }

    private enum SettledScrollCommand {
        case top
        case bottom
        case offset(CGFloat)
    }

    private func scheduleSettledScroll(
        _ command: SettledScrollCommand,
        measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator?,
        scrollController: ScrollController
    ) {
        nextRequestID()
        settledScrollExecutor.execute(
            settledScrollCommand(for: command),
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController
        )
    }

    private func settledScrollCommand(for command: SettledScrollCommand) -> ClipboardSettledScrollExecutor.Command {
        switch command {
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .offset(let offset):
            return .offset(offset)
        }
    }

    @discardableResult
    private func nextRequestID() -> UInt {
        scrollRequestID &+= 1
        return scrollRequestID
    }
}
