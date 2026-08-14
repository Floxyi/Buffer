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
        projectedDisplayState(for: state.contentSnapshot, cache: listCache)
    }

    var body: some View {
        let currentDisplayState = displayState

        ClipboardListContent(
            scrollController: scrollController,
            scrollCoordinator: scrollCoordinator,
            measuredScrollCoordinator: measuredScrollCoordinator,
            contextMenuState: contextMenuState,
            hoverCoordinator: hoverCoordinator,
            items: items,
            displayRowsForRendering: currentDisplayState.displayRows,
            contentTrailingPadding: currentDisplayState.contentTrailingPadding,
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
            primaryLabelText: { currentDisplayState.cache.primaryLabelText(for: $0) },
            indexForItem: { currentDisplayState.cache.index(for: $0, in: items) },
            onScrollViewReady: configureScrollView(_:),
            onScrollToTopRequested: handleScrollToTopRequest(using:),
            onMeasuredTargetFrameChanged: handleMeasuredTargetFrameChanged(_:),
            onMenuTrackingEnded: handleMenuTrackingEnded,
            onAppear: handleAppear(using:)
        )
        .onDisappear(perform: handleDisappear)
        .onChange(of: state.contentSnapshot) { snapshot in
            handleContentChange(snapshot)
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
        let currentDisplayState = displayState
        let currentItems = items
        return makeScrollContext(items: currentItems, displayState: currentDisplayState)
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
        let currentDisplayState = displayState
        configureMetricsCallback(items: items, layoutIndex: currentDisplayState.layoutIndex)
    }

    private func configureMetricsCallback(
        items: [ClipboardItem],
        layoutIndex: ClipboardListLayoutIndex
    ) {
        scrollController.onMetricsChanged = { [assetPrewarmer, hoverCoordinator] metrics in
            hoverCoordinator.suppressUntilPointerMoves()
            assetPrewarmer.prewarmVisibleAssets(
                in: items,
                layoutIndex: layoutIndex,
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
        let snapshot = state.contentSnapshot
        let cache = rebuildListCache(for: snapshot)
        let currentDisplayState = projectedDisplayState(for: snapshot, cache: cache)
        installKeyboardScrollHandler(items: snapshot.items, displayState: currentDisplayState)
        lifecycleCoordinator.handleAppear(
            items: snapshot.items,
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
        updateVisibleAssetPrewarm(items: snapshot.items, layoutIndex: currentDisplayState.layoutIndex)
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
        let currentDisplayState = displayState
        updateVisibleAssetPrewarm(items: items, layoutIndex: currentDisplayState.layoutIndex)
    }

    private func updateVisibleAssetPrewarm(
        items: [ClipboardItem],
        layoutIndex: ClipboardListLayoutIndex
    ) {
        assetPrewarmer.prewarmVisibleAssets(
            in: items,
            layoutIndex: layoutIndex,
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
            rebuildListCache: {
                _ = rebuildListCache(for: state.contentSnapshot)
            }
        )
    }

    private func handleContentChange(_ snapshot: ClipboardListContentSnapshot) {
        let cache = rebuildListCache(for: snapshot)
        let currentDisplayState = projectedDisplayState(for: snapshot, cache: cache)
        installKeyboardScrollHandler(items: snapshot.items, displayState: currentDisplayState)
        configureMetricsCallback(items: snapshot.items, layoutIndex: currentDisplayState.layoutIndex)
        updateVisibleAssetPrewarm(items: snapshot.items, layoutIndex: currentDisplayState.layoutIndex)
    }

    @discardableResult
    private func rebuildListCache(
        for snapshot: ClipboardListContentSnapshot
    ) -> ClipboardListStructure.DisplayCache {
        let cache = ClipboardListStructure.makeDisplayCache(
            from: snapshot.items,
            sourceSnapshotID: snapshot.id
        )
        listCache = cache
        return cache
    }

    private func projectedDisplayState(
        for snapshot: ClipboardListContentSnapshot,
        cache: ClipboardListStructure.DisplayCache
    ) -> ClipboardListDisplayState {
        displayStateProjector.project(
            items: snapshot.items,
            itemsSnapshotID: snapshot.id,
            cache: cache,
            viewportHeight: scrollController.viewportHeight
        )
    }

    private func makeScrollContext(
        items: [ClipboardItem],
        displayState: ClipboardListDisplayState
    ) -> ClipboardListScrollContext {
        ClipboardListScrollContext(
            items: items,
            displayRows: displayState.displayRows,
            layoutIndex: displayState.layoutIndex,
            itemExists: { displayState.cache.itemExists($0, in: items) },
            scrollMetrics: { scrollController.currentMetrics() },
            onJumpScrollStarted: actions.jumpScrollStarted,
            onJumpScrollCompleted: actions.jumpScrollCompleted,
            log: { message in
                logScrollDiagnostics(message)
            }
        )
    }

    private func installKeyboardScrollHandler(
        items: [ClipboardItem],
        displayState: ClipboardListDisplayState
    ) {
        let currentContext = makeScrollContext(items: items, displayState: displayState)
        keyboardScrollRegistrationID = keyboardScrollRouter.register {
            [weak scrollCoordinator, weak scrollController, weak assetPrewarmer] request in
            guard let scrollCoordinator, let scrollController, let assetPrewarmer else { return }
            scrollCoordinator.handleKeyboardScrollRequestChange(
                request,
                items: items,
                assetPrewarmer: assetPrewarmer,
                scrollController: scrollController,
                context: currentContext
            )
        }
    }

    private func logScrollDiagnostics(_ message: @autoclosure () -> String) {
        #if DEBUG
            let resolvedMessage = message()
            BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
        #endif
    }
}
