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
    @State private var assetPrewarmer = ClipboardListAssetPrewarmer()
    private let lifecycleCoordinator = ClipboardListLifecycleCoordinator()
    private let displayStateProjector = ClipboardListDisplayStateProjector()

    let items: [ClipboardItem]

    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool

    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let onCommitSelection: () -> Void
    let onDismiss: () -> Void

    @Binding var selectedIDs: Set<UUID>

    var onSelectSingle: (UUID, Int) -> Void = { _, _ in }
    var onSelectPreferredTopItem: () -> UUID? = { nil }
    var onToggleSelection: (UUID) -> Void = { _ in }
    var onExtendSelectionTo: (UUID) -> Void = { _ in }
    var contextMenuActions: (UUID) -> [HistoryItemActionDescriptor] = { _ in [] }
    var onContextMenuAction: (UUID, HistoryItemAction) -> Void = { _, _ in }
    var selectionNavigationToken: Int = 0
    var selectedItemID: UUID? = nil
    var openScrollRequest: HistoryViewModel.OpenListScrollRequest? = nil
    var openScrollRequestToken: Int = 0
    var isShowingFullHistory = false
    var keyboardScrollRequest: HistoryViewModel.KeyboardScrollRequest? = nil

    /// Dedicated jump-to-history request. This must stay separate from open/keyboard scrolling.
    var jumpScrollRequest: HistoryViewModel.JumpToHistoryRequest? = nil
    var onJumpScrollStarted: (HistoryViewModel.JumpToHistoryRequest) -> Void = { _ in }
    var onJumpScrollCompleted: (HistoryViewModel.JumpToHistoryRequest, Bool) -> Void = { _, _ in }

    var onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void) = { _ in }
    var onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void) = { _ in }

    private var itemIDs: [UUID] {
        items.map(\.id)
    }

    private var jumpScrollTaskKey: ClipboardListJumpScrollTaskKey {
        scrollCoordinator.jumpScrollTaskKey(
            request: jumpScrollRequest,
            itemCount: items.count,
            isShowingFullHistory: isShowingFullHistory
        )
    }

    private var displayState: ClipboardListDisplayState {
        displayStateProjector.project(
            items: items,
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
            store: store,
            settings: settings,
            quickPasteBadgeNumberByItemID: quickPasteBadgeNumberByItemID,
            selectedIDs: selectedIDs,
            isAwaitingInitialOpenScroll: scrollCoordinator.isAwaitingInitialOpenScroll,
            onCommitSelection: onCommitSelection,
            onSelectSingle: onSelectSingle,
            onToggleSelection: onToggleSelection,
            onExtendSelectionTo: onExtendSelectionTo,
            contextMenuActions: contextMenuActions,
            onContextMenuAction: onContextMenuAction,
            primaryLabelText: primaryLabelText(for:),
            indexForItem: index(for:),
            onScrollViewReady: configureScrollView(_:),
            onScrollToTopRequested: handleScrollToTopRequest(using:),
            onMeasuredTargetFrameChanged: handleMeasuredTargetFrameChanged(_:),
            onMenuTrackingEnded: handleMenuTrackingEnded,
            onAppear: handleAppear(using:)
        )
        .onDisappear(perform: handleDisappear)
        .onChange(of: itemIDs) { _ in
            rebuildListCache()
            configureMetricsCallback()
            updateVisibleAssetPrewarm()
        }
        .onChange(of: scrollController.viewportHeight) { _ in
            updateVisibleAssetPrewarm()
        }
        .onChange(of: openScrollRequestToken) { _ in
            applyOpenScrollRequestIfPossible()
        }
        .onChange(of: selectedIndex) { newValue in
            scrollCoordinator.handleSelectedIndexChange(
                selectedIndex: newValue,
                itemCount: items.count,
                itemID: items[safe: newValue]?.id,
                scrollTrigger: &scrollTrigger,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: scrollContext
            )
        }
        .onChange(of: selectionNavigationToken) { _ in
            guard let selectedItemID else { return }
            guard jumpScrollRequest?.itemID != selectedItemID else { return }
            guard let pendingScrollProxy else { return }

            scrollCoordinator.handleSelectionNavigation(
                to: selectedItemID,
                using: pendingScrollProxy,
                measuredScrollCoordinator: measuredScrollCoordinator,
                scrollController: scrollController,
                context: scrollContext
            )
        }
        .onChange(of: keyboardScrollRequest) { newRequest in
            scrollCoordinator.handleKeyboardScrollRequestChange(
                newRequest,
                items: items,
                store: store,
                settings: settings,
                assetPrewarmer: assetPrewarmer,
                scrollController: scrollController,
                context: scrollContext
            )
        }
        .onChange(of: jumpScrollRequest) { newRequest in
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
            onJumpScrollStarted: onJumpScrollStarted,
            onJumpScrollCompleted: onJumpScrollCompleted,
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
                viewportHeight: metrics.viewportHeight,
                store: store,
                settings: settings
            )
        }
    }

    private func handleScrollToTopRequest(using scrollProxy: ScrollViewProxy) {
        pendingScrollProxy = scrollProxy
        scrollCoordinator.selectFirstItemAndScrollToTop(
            preferredTopItemID: onSelectPreferredTopItem(),
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
        lifecycleCoordinator.handleAppear(
            items: items,
            settings: settings,
            prewarmVisibleAssets: { items, settings in
                assetPrewarmer.prewarmVisibleAssets(in: items, store: store, settings: settings)
            },
            currentScrollOffsetSnapshot: {
                scrollController.currentScrollOffsetSnapshot()
            },
            syncScrollMetrics: {
                scrollController.syncMetricsImmediately()
            },
            onScrollOffsetProviderChanged: onScrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: onScrollOffsetRestorerChanged,
            restoreScrollOffset: restoreScrollOffset(_:),
            applyOpenScrollRequestIfPossible: applyOpenScrollRequestIfPossible
        )
        updateVisibleAssetPrewarm()
    }

    private func handleDisappear() {
        scrollController.onMetricsChanged = nil
        hoverCoordinator.reset()
        lifecycleCoordinator.handleDisappear(
            cancelVisibleAssetPrewarm: {
                assetPrewarmer.cancelAll()
            },
            cancelScrolling: {
                scrollCoordinator.cancelAll(measuredScrollCoordinator: measuredScrollCoordinator)
            },
            onScrollOffsetProviderChanged: onScrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: onScrollOffsetRestorerChanged
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
            request: openScrollRequest,
            requestToken: openScrollRequestToken,
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
            viewportHeight: scrollController.viewportHeight,
            store: store,
            settings: settings
        )
    }

    private func runJumpScrollTaskIfNeeded() async {
        guard let jumpScrollRequest, let pendingScrollProxy else {
            return
        }

        await scrollCoordinator.waitAndStartJumpScrollIfReady(
            jumpScrollRequest,
            currentJumpScrollRequest: { self.jumpScrollRequest },
            isShowingFullHistory: { self.isShowingFullHistory },
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
