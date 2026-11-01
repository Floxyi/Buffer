import AppKit
import SwiftUI

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @StateObject private var scrollController = ScrollController()
    @StateObject private var scrollCoordinator = ClipboardListScrollCoordinator()
    @StateObject private var contextMenuState = ClipboardListContextMenuState()
    @StateObject private var pinnedReorderCoordinator = ClipboardPinnedReorderCoordinator()
    @StateObject private var viewportPreserver = ClipboardListViewportPreserver()
    @StateObject private var renderingWindowCoordinator = ClipboardListRenderingWindowCoordinator()
    @State private var hoverCoordinator = ClipboardListHoverCoordinator()
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
        let snapshot = state.contentSnapshot
        return projectedDisplayState(
            for: snapshot,
            cache: snapshot.displayCache
        )
    }

    var body: some View {
        let currentDisplayState = displayState
        let snapshot = state.contentSnapshot
        let viewportTransition = viewportPreserver.transition(for: snapshot)
        let renderingWindow = renderingWindowCoordinator.resolvedWindow(
            snapshotID: snapshot.id,
            query: snapshot.query,
            layoutIndex: currentDisplayState.layoutIndex,
            scrollOffset: scrollController.scrollOffset,
            viewportHeight: scrollController.viewportHeight,
            pinnedItemCount: currentDisplayState.cache.pinnedItemIDs.count
        )

        ClipboardListContent(
            scrollController: scrollController,
            scrollCoordinator: scrollCoordinator,
            contextMenuState: contextMenuState,
            pinnedReorderCoordinator: pinnedReorderCoordinator,
            hoverCoordinator: hoverCoordinator,
            items: items,
            pinnedItemIDs: currentDisplayState.cache.pinnedItemIDs,
            displayRowsForRendering: currentDisplayState.displayRows,
            renderingWindow: renderingWindow,
            contentHeight: currentDisplayState.layoutIndex.contentHeight,
            viewportTransition: viewportTransition,
            contentTrailingPadding: currentDisplayState.contentTrailingPadding,
            websitePreviewsEnabled: websitePreviewsEnabled,
            assetProvider: assetProvider,
            quickPasteBadgeNumberByItemID: state.quickPasteBadgeNumberByItemID,
            selectedIDs: state.selectedIDs,
            searchResultsByItemID: state.searchResultsByItemID,
            queryText: state.queryText,
            committedQueryText: state.committedQueryText,
            searchResultAnimationID: state.committedQueryText.isEmpty
                ? nil : state.itemsSnapshotID,
            searchResultAnimationPolicy:
                state.committedQueryText.isEmpty
                ? .disabled
                : SearchResultAnimationPolicy.make(
                    resultCount: items.count,
                    reduceMotion: accessibilityReduceMotion
                ),
            allowsPinnedReordering: state.allowsPinnedReordering,
            reduceMotion: accessibilityReduceMotion,
            onCommitSelection: actions.commitSelection,
            onSelectSingle: actions.selectSingle,
            onToggleSelection: actions.toggleSelection,
            onExtendSelectionTo: actions.extendSelection,
            contextMenuActions: actions.contextMenuActions,
            onContextMenuAction: actions.performContextMenuAction,
            onReorderPinnedItems: actions.reorderPinnedItems,
            primaryLabelText: { currentDisplayState.cache.primaryLabelText(for: $0) },
            indexForItem: { currentDisplayState.cache.index(for: $0, in: items) },
            itemForID: { currentDisplayState.cache.item(for: $0, in: items) },
            onScrollViewReady: configureScrollView(_:),
            onScrollToTopRequested: handleScrollToTopRequest,
            onMenuTrackingEnded: handleMenuTrackingEnded,
            onAppear: handleAppear
        )
        .onDisappear(perform: handleDisappear)
        .onChange(of: state.contentSnapshot) { _, snapshot in
            handleContentChange(snapshot)
        }
        .onChange(of: state.allowsPinnedReordering) {
            synchronizePinnedReordering()
        }
        .onChange(of: scrollController.viewportHeight) {
            updateVisibleAssetPrewarm()
        }
        .onChange(of: navigation.openScrollRequestToken) {
            applyOpenScrollRequestIfPossible()
        }
        .onChange(of: navigation.jumpScrollRequest) { _, newRequest in
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

    private func configureScrollView(_ scrollView: NSScrollView) {
        scrollController.configure(
            scrollView: scrollView,
            interactionMode: .system
        )
        scrollController.onUserScrollStarted = {
            [
                weak scrollCoordinator,
                weak scrollController,
                weak viewportPreserver,
            ] in
            guard let scrollCoordinator, let scrollController else { return }
            scrollCoordinator.cancelAll()
            viewportPreserver?.cancel(scrollController: scrollController)
        }
        configureMetricsCallback()
    }

    private func configureMetricsCallback() {
        let currentDisplayState = displayState
        configureMetricsCallback(
            items: items,
            layoutIndex: currentDisplayState.layoutIndex
        )
    }

    private func configureMetricsCallback(
        items: [ClipboardItem],
        layoutIndex: ClipboardListLayoutIndex
    ) {
        let snapshotID = state.contentSnapshot.id
        let query = state.contentSnapshot.query
        let pinnedItemCount = state.preparedDisplayCache.pinnedItemIDs.count
        scrollController.onMetricsChanged = {
            [
                assetPrewarmer,
                hoverCoordinator,
                renderingWindowCoordinator,
                actions,
            ] metrics in
            hoverCoordinator.suppressUntilPointerMoves()
            renderingWindowCoordinator.update(
                snapshotID: snapshotID,
                query: query,
                layoutIndex: layoutIndex,
                scrollOffset: metrics.scrollOffset,
                viewportHeight: metrics.viewportHeight,
                pinnedItemCount: pinnedItemCount
            )
            assetPrewarmer.prewarmVisibleAssets(
                in: items,
                layoutIndex: layoutIndex,
                scrollOffset: metrics.scrollOffset,
                viewportHeight: metrics.viewportHeight
            )
            actions.visibleItemIDsChanged(
                layoutIndex.visibleItemIDs(
                    scrollOffset: metrics.scrollOffset,
                    viewportHeight: metrics.viewportHeight,
                    overscan: 88
                )
            )
        }
    }

    private func handleScrollToTopRequest() {
        scrollCoordinator.selectFirstItemAndScrollToTop(
            preferredTopItemID: actions.selectPreferredTopItem(),
            firstItemID: items.first?.id,
            scrollController: scrollController,
            context: scrollContext
        )
    }

    private func handleMenuTrackingEnded() {
        contextMenuState.clear()
    }

    private func handleAppear() {
        let snapshot = state.contentSnapshot
        let cache = validatedDisplayCache(for: snapshot)
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
        renderingWindowCoordinator.update(
            snapshotID: snapshot.id,
            query: snapshot.query,
            layoutIndex: currentDisplayState.layoutIndex,
            scrollOffset: scrollController.currentScrollOffsetSnapshot(),
            viewportHeight: scrollController.currentViewportHeightSnapshot(),
            pinnedItemCount: currentDisplayState.cache.pinnedItemIDs.count
        )
        synchronizePinnedReordering(cache: cache)
        actions.viewportPreservationHandlerChanged(
            ClipboardListViewportPreservationHandler(
                prepareForRemoval: {
                    [
                        weak scrollCoordinator,
                        weak scrollController,
                        weak viewportPreserver,
                        hoverCoordinator,
                    ] itemIDs, snapshot in
                    guard
                        let scrollCoordinator,
                        let scrollController,
                        let viewportPreserver
                    else { return }
                    scrollCoordinator.cancelAll()
                    hoverCoordinator.suppressUntilPointerMoves()
                    viewportPreserver.prepareForRemoval(
                        itemIDs,
                        from: snapshot,
                        scrollController: scrollController
                    )
                },
                cancel: { [weak scrollController, weak viewportPreserver] in
                    guard let scrollController, let viewportPreserver else { return }
                    viewportPreserver.cancel(scrollController: scrollController)
                }
            )
        )
    }

    private func handleDisappear() {
        if let keyboardScrollRegistrationID {
            keyboardScrollRouter.unregister(keyboardScrollRegistrationID)
            self.keyboardScrollRegistrationID = nil
        }
        scrollController.onMetricsChanged = nil
        scrollController.onUserScrollStarted = nil
        actions.viewportPreservationHandlerChanged(nil)
        viewportPreserver.cancel(scrollController: scrollController)
        hoverCoordinator.reset()
        lifecycleCoordinator.handleDisappear(
            cancelVisibleAssetPrewarm: {
                assetPrewarmer.cancelAll()
            },
            cancelScrolling: {
                scrollCoordinator.cancelAll()
            },
            onScrollOffsetProviderChanged: actions.scrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: actions.scrollOffsetRestorerChanged
        )
    }

    private func restoreScrollOffset(_ offset: CGFloat) {
        scrollCoordinator.restoreScrollOffsetForReopen(
            offset,
            scrollController: scrollController
        )
    }

    private func applyOpenScrollRequestIfPossible() {
        scrollCoordinator.applyOpenScrollRequestIfNeeded(
            request: navigation.openScrollRequest,
            requestToken: navigation.openScrollRequestToken,
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
        guard let jumpScrollRequest = navigation.jumpScrollRequest else { return }

        await scrollCoordinator.waitAndStartJumpScrollIfReady(
            jumpScrollRequest,
            currentJumpScrollRequest: { self.navigation.jumpScrollRequest },
            isShowingFullHistory: { self.navigation.isShowingFullHistory },
            scrollController: scrollController,
            context: scrollContext
        )
    }

    private func handleContentChange(_ snapshot: ClipboardListContentSnapshot) {
        let cache = validatedDisplayCache(for: snapshot)
        let currentDisplayState = projectedDisplayState(for: snapshot, cache: cache)
        installKeyboardScrollHandler(items: snapshot.items, displayState: currentDisplayState)
        configureMetricsCallback(
            items: snapshot.items,
            layoutIndex: currentDisplayState.layoutIndex
        )
        viewportPreserver.contentDidChange(
            to: snapshot,
            scrollController: scrollController
        )
        renderingWindowCoordinator.update(
            snapshotID: snapshot.id,
            query: snapshot.query,
            layoutIndex: currentDisplayState.layoutIndex,
            scrollOffset: scrollController.currentScrollOffsetSnapshot(),
            viewportHeight: scrollController.currentViewportHeightSnapshot(),
            pinnedItemCount: currentDisplayState.cache.pinnedItemIDs.count
        )
        updateVisibleAssetPrewarm(items: snapshot.items, layoutIndex: currentDisplayState.layoutIndex)
        synchronizePinnedReordering(cache: cache)
    }

    private func synchronizePinnedReordering(
        cache: ClipboardListStructure.DisplayCache? = nil
    ) {
        pinnedReorderCoordinator.synchronize(
            authoritativeItemIDs: (cache ?? state.preparedDisplayCache).pinnedItemIDs,
            allowsReordering: state.allowsPinnedReordering
        )
    }

    @discardableResult
    private func validatedDisplayCache(
        for snapshot: ClipboardListContentSnapshot
    ) -> ClipboardListStructure.DisplayCache {
        let cache = snapshot.displayCache
        assert(
            cache.matches(sourceSnapshotID: snapshot.id),
            "A list publication must include its matching display cache"
        )
        return cache
    }

    private func projectedDisplayState(
        for snapshot: ClipboardListContentSnapshot,
        cache: ClipboardListStructure.DisplayCache
    ) -> ClipboardListDisplayState {
        displayStateProjector.project(
            snapshotID: snapshot.id,
            cache: cache,
            viewportHeight: scrollController.viewportHeight
        )
    }

    private func makeScrollContext(
        items: [ClipboardItem],
        displayState: ClipboardListDisplayState
    ) -> ClipboardListScrollContext {
        ClipboardListScrollContext(
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
