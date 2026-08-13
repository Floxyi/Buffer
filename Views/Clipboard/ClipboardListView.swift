import AppKit
import SwiftUI

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    @StateObject private var scrollController = ScrollController()
    @StateObject private var scrollCoordinator = ClipboardListScrollCoordinator()
    @StateObject private var measuredScrollCoordinator = ClipboardMeasuredScrollCoordinator()
    @StateObject private var contextMenuState = ClipboardListContextMenuState()
    @State private var hoverCoordinator = ClipboardListHoverCoordinator()
    @State private var listCache = ClipboardListStructure.DisplayCache.empty
    @State private var keyboardScrollRegistrationID: UUID?
    private let lifecycleCoordinator = ClipboardListLifecycleCoordinator()
    private let displayStateProjector = ClipboardListDisplayStateProjector()

    let state: ClipboardListViewState
    let navigation: ClipboardListNavigationState
    let actions: ClipboardListActions

    let websitePreviewsEnabled: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let assetPrewarmer: ClipboardListAssetPrewarmer
    let keyboardScrollRouter: HistoryKeyboardScrollRouter

    private var items: [ClipboardItem] { state.items }

    private var jumpScrollTaskKey: ClipboardListJumpScrollTaskKey {
        scrollCoordinator.jumpScrollTaskKey(
            request: navigation.jumpScrollRequest,
            itemCount: items.count,
            isShowingFullHistory: navigation.isShowingFullHistory
        )
    }

    private var displayState: ClipboardListDisplayState {
        displayStateProjector.project(
            cache: listCache,
            viewportHeight: scrollController.viewportHeight
        )
    }

    var body: some View {
        ClipboardListContent(
            scrollController: scrollController,
            scrollCoordinator: scrollCoordinator,
            measuredScrollCoordinator: measuredScrollCoordinator,
            contextMenuState: contextMenuState,
            hoverCoordinator: hoverCoordinator,
            items: items,
            displayRowsForRendering: displayState.displayRows,
            contentTrailingPadding: displayState.contentTrailingPadding,
            websitePreviewsEnabled: websitePreviewsEnabled,
            assetProvider: assetProvider,
            quickPasteBadgeNumberByItemID: state.quickPasteBadgeNumberByItemID,
            selectedIDs: state.selectedIDs,
            searchResultsByItemID: state.searchResultsByItemID,
            queryText: state.queryText,
            isAwaitingInitialOpenScroll: scrollCoordinator.isAwaitingInitialOpenScroll,
            onCommitSelection: actions.commitSelection,
            onSelectSingle: actions.selectSingle,
            onToggleSelection: actions.toggleSelection,
            onExtendSelectionTo: actions.extendSelection,
            contextMenuActions: actions.contextMenuActions,
            onContextMenuAction: actions.performContextMenuAction,
            primaryLabelText: primaryLabelText(for:),
            indexForItem: index(for:),
            onScrollViewReady: configureScrollView(_:),
            onScrollToTopRequested: handleScrollToTopRequest(using:),
            onMeasuredTargetFrameChanged: handleMeasuredTargetFrameChanged(_:),
            onMenuTrackingEnded: handleMenuTrackingEnded,
            onAppear: handleAppear(using:)
        )
        .onDisappear(perform: handleDisappear)
        .onChange(of: state.itemsRevision) { _ in
            rebuildListCache()
            installKeyboardScrollHandler()
            configureMetricsCallback()
            updateVisibleAssetPrewarm()
        }
        .onChange(of: scrollController.viewportHeight) { _ in
            updateVisibleAssetPrewarm()
        }
        .onChange(of: navigation.openScrollRequestToken) { _ in
            applyOpenScrollRequestIfPossible()
        }
        .onChange(of: navigation.jumpScrollRequest) { newRequest in
            scrollCoordinator.syncJumpScrollRequest(newRequest)
        }
        .task(id: jumpScrollTaskKey) {
            await runJumpScrollTaskIfNeeded()
        }
    }

    private var scrollContext: ClipboardListScrollContext {
        ClipboardListScrollContext(
            items: items,
            displayRows: displayState.displayRows,
            layoutIndex: displayState.layoutIndex,
            itemExists: itemExists(_:),
            scrollMetrics: { scrollController.currentMetrics() },
            onJumpScrollStarted: actions.jumpScrollStarted,
            onJumpScrollCompleted: actions.jumpScrollCompleted,
            log: { message in
                logScrollDiagnostics(message)
            }
        )
    }

    @State private var pendingScrollProxy: ScrollViewProxy?

    private func configureScrollView(_ scrollView: NSScrollView) {
        scrollController.configure(
            scrollView: scrollView,
            interactionMode: .system
        )
        configureMetricsCallback()
    }

    private func configureMetricsCallback() {
        scrollController.onMetricsChanged = { [assetPrewarmer, hoverCoordinator] metrics in
            hoverCoordinator.suppressUntilPointerMoves()
            assetPrewarmer.prewarmVisibleAssets(
                in: items,
                layoutIndex: displayState.layoutIndex,
                scrollOffset: metrics.scrollOffset,
                viewportHeight: metrics.viewportHeight
            )
        }
    }

    private func handleScrollToTopRequest(using scrollProxy: ScrollViewProxy) {
        pendingScrollProxy = scrollProxy
        scrollCoordinator.selectFirstItemAndScrollToTop(
            preferredTopItemID: actions.selectPreferredTopItem(),
            firstItemID: items.first?.id,
            using: scrollProxy,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController,
            context: scrollContext
        )
    }

    private func handleMeasuredTargetFrameChanged(_ frame: CGRect?) {
        scrollCoordinator.handleMeasuredTargetFrameChange(
            frame,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController,
            context: scrollContext
        )
    }

    private func handleMenuTrackingEnded() {
        contextMenuState.clear()
    }

    private func handleAppear(using scrollProxy: ScrollViewProxy) {
        pendingScrollProxy = scrollProxy
        rebuildListCache()
        installKeyboardScrollHandler()
        lifecycleCoordinator.handleAppear(
            items: items,
            prewarmVisibleAssets: { items in
                assetPrewarmer.prewarmVisibleAssets(in: items)
            },
            currentScrollOffsetSnapshot: {
                scrollController.currentScrollOffsetSnapshot()
            },
            syncScrollMetrics: {
                scrollController.syncMetricsImmediately()
            },
            onScrollOffsetProviderChanged: actions.scrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: actions.scrollOffsetRestorerChanged,
            restoreScrollOffset: restoreScrollOffset(_:),
            applyOpenScrollRequestIfPossible: applyOpenScrollRequestIfPossible
        )
        updateVisibleAssetPrewarm()
    }

    private func handleDisappear() {
        if let keyboardScrollRegistrationID {
            keyboardScrollRouter.unregister(keyboardScrollRegistrationID)
            self.keyboardScrollRegistrationID = nil
        }
        scrollController.onMetricsChanged = nil
        hoverCoordinator.reset()
        lifecycleCoordinator.handleDisappear(
            cancelVisibleAssetPrewarm: {
                assetPrewarmer.cancelAll()
            },
            cancelScrolling: {
                scrollCoordinator.cancelAll(measuredScrollCoordinator: measuredScrollCoordinator)
            },
            onScrollOffsetProviderChanged: actions.scrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: actions.scrollOffsetRestorerChanged
        )
        pendingScrollProxy = nil
    }

    private func restoreScrollOffset(_ offset: CGFloat) {
        scrollCoordinator.restoreScrollOffsetForReopen(
            offset,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController
        )
    }

    private func applyOpenScrollRequestIfPossible() {
        guard let pendingScrollProxy else { return }
        scrollCoordinator.applyOpenScrollRequestIfNeeded(
            request: navigation.openScrollRequest,
            requestToken: navigation.openScrollRequestToken,
            using: pendingScrollProxy,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController,
            context: scrollContext
        )
    }

    private func updateVisibleAssetPrewarm() {
        assetPrewarmer.prewarmVisibleAssets(
            in: items,
            layoutIndex: displayState.layoutIndex,
            scrollOffset: scrollController.scrollOffset,
            viewportHeight: scrollController.viewportHeight
        )
    }

    private func runJumpScrollTaskIfNeeded() async {
        guard let jumpScrollRequest = navigation.jumpScrollRequest, let pendingScrollProxy else {
            return
        }

        await scrollCoordinator.waitAndStartJumpScrollIfReady(
            jumpScrollRequest,
            currentJumpScrollRequest: { self.navigation.jumpScrollRequest },
            isShowingFullHistory: { self.navigation.isShowingFullHistory },
            using: pendingScrollProxy,
            measuredScrollCoordinator: measuredScrollCoordinator,
            scrollController: scrollController,
            context: scrollContext,
            rebuildListCache: rebuildListCache
        )
    }

    private func rebuildListCache() {
        listCache = ClipboardListStructure.makeDisplayCache(from: items)
    }

    private func installKeyboardScrollHandler() {
        let currentItems = items
        let currentContext = scrollContext
        keyboardScrollRegistrationID = keyboardScrollRouter.register {
            [weak scrollCoordinator, weak scrollController, weak assetPrewarmer] request in
            guard let scrollCoordinator, let scrollController, let assetPrewarmer else { return }
            scrollCoordinator.handleKeyboardScrollRequestChange(
                request,
                items: currentItems,
                assetPrewarmer: assetPrewarmer,
                scrollController: scrollController,
                context: currentContext
            )
        }
    }

    private func primaryLabelText(for item: ClipboardItem) -> String {
        listCache.primaryLabelText(for: item)
    }

    private func index(for item: ClipboardItem) -> Int {
        listCache.index(for: item, in: items)
    }

    private func itemExists(_ itemID: UUID) -> Bool {
        listCache.itemExists(itemID, in: items)
    }

    private func logScrollDiagnostics(_ message: @autoclosure () -> String) {
        #if DEBUG
            let resolvedMessage = message()
            BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
        #endif
    }
}
