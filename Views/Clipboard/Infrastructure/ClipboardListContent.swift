import AppKit
import SwiftUI

struct ClipboardListContent: View {
    let scrollController: ScrollController
    @ObservedObject var scrollCoordinator: ClipboardListScrollCoordinator
    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var pinnedReorderCoordinator: ClipboardPinnedReorderCoordinator
    let hoverCoordinator: ClipboardListHoverCoordinator

    let items: [ClipboardItem]
    let pinnedItemIDs: [UUID]
    let displayRowsForRendering: [ClipboardListStructure.DisplayRow]
    let renderingWindow: ClipboardListRenderingWindow
    let contentHeight: CGFloat
    let viewportTransition: ClipboardListViewportTransition
    let contentTrailingPadding: CGFloat
    let websitePreviewsEnabled: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let searchResultsByItemID: [UUID: ClipboardSearchHit]
    let queryText: String
    let committedQueryText: String
    let searchResultAnimationID: UUID?
    let searchResultAnimationPolicy: SearchResultAnimationPolicy
    let allowsPinnedReordering: Bool
    let reduceMotion: Bool
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onReorderPinnedItems: (ClipboardPinnedReorderRequest) async -> Bool
    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int
    let itemForID: (UUID) -> ClipboardItem?
    let onScrollViewReady: (NSScrollView) -> Void
    let onScrollToTopRequested: () -> Void
    let onMenuTrackingEnded: () -> Void
    let onAppear: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ClipboardListRowsSection(
                rows: displayRowsForRendering,
                renderingWindow: renderingWindow,
                items: items,
                pinnedItemIDs: pinnedItemIDs,
                websitePreviewsEnabled: websitePreviewsEnabled,
                assetProvider: assetProvider,
                quickPasteBadgeNumberByItemID: quickPasteBadgeNumberByItemID,
                selectedIDs: selectedIDs,
                searchResultsByItemID: searchResultsByItemID,
                queryText: queryText,
                committedQueryText: committedQueryText,
                searchResultAnimationPolicy: searchResultAnimationPolicy,
                allowsPinnedReordering: allowsPinnedReordering,
                reduceMotion: reduceMotion,
                onCommitSelection: onCommitSelection,
                onSelectSingle: onSelectSingle,
                onToggleSelection: onToggleSelection,
                onExtendSelectionTo: onExtendSelectionTo,
                contextMenuActions: contextMenuActions,
                onContextMenuAction: onContextMenuAction,
                onReorderPinnedItems: onReorderPinnedItems,
                contextMenuState: contextMenuState,
                pinnedReorderCoordinator: pinnedReorderCoordinator,
                scrollController: scrollController,
                hoverCoordinator: hoverCoordinator,
                primaryLabelText: primaryLabelText,
                indexForItem: indexForItem,
                itemForID: itemForID
            )
            .animation(
                searchResultAnimationID == nil
                    ? nil : searchResultAnimationPolicy.insertion,
                value: searchResultAnimationID
            )
            .padding(.vertical, ClipboardListStructure.LayoutMetrics.contentPadding)
            .padding(.leading, ClipboardListStructure.LayoutMetrics.contentPadding)
            .padding(.trailing, contentTrailingPadding)
            .offset(y: viewportTransition.contentOffset)
            // Keep the authoritative document height in the hierarchy while a
            // deletion swaps the bounded row window. This prevents AppKit from
            // clamping a deep viewport to an intermediate SwiftUI measurement.
            .frame(
                minHeight: max(contentHeight, viewportTransition.minimumContentHeight),
                alignment: .top
            )
            .background {
                ScrollViewConfigurator(
                    configure: { scrollView in
                        scrollView.hasVerticalScroller = false
                        scrollView.autohidesScrollers = true
                        scrollView.scrollerStyle = .overlay

                        scrollView.automaticallyAdjustsContentInsets = false
                        scrollView.verticalScrollElasticity = .none
                        scrollView.horizontalScrollElasticity = .none

                        onScrollViewReady(scrollView)
                    },
                    searchStrategy: .nearestAncestorOnly
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("historyList.scrollView")
        .overlay(alignment: .bottom) {
            ClipboardScrollToTopOverlay(scrollController: scrollController) {
                onMenuTrackingEnded()
                onScrollToTopRequested()
            }
        }
        .overlay(alignment: .topTrailing) {
            ClipboardScrollbarOverlay(scrollController: scrollController)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            onMenuTrackingEnded()
        }
        .onAppear(perform: onAppear)
    }
}
