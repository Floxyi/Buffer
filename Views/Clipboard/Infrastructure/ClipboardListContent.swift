import AppKit
import SwiftUI

struct ClipboardListContent: View {
    let scrollController: ScrollController
    @ObservedObject var scrollCoordinator: ClipboardListScrollCoordinator
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator
    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var pinnedReorderCoordinator: ClipboardPinnedReorderCoordinator
    let hoverCoordinator: ClipboardListHoverCoordinator

    let items: [ClipboardItem]
    let pinnedItemIDs: [UUID]
    let displayRowsForRendering: [ClipboardListStructure.DisplayRow]
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
    let isAwaitingInitialOpenScroll: Bool
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
    let onScrollToTopRequested: (ScrollViewProxy) -> Void
    let onMeasuredTargetFrameChanged: (CGRect?) -> Void
    let onMenuTrackingEnded: () -> Void
    let onAppear: (ScrollViewProxy) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                ClipboardListRowsSection(
                    rows: displayRowsForRendering,
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
                    measuredScrollCoordinator: measuredScrollCoordinator,
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
                .coordinateSpace(name: ClipboardListCoordinateSpace.content)
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
            .overlay(alignment: .bottom) {
                ClipboardScrollToTopOverlay(scrollController: scrollController) {
                    onMenuTrackingEnded()
                    onScrollToTopRequested(scrollProxy)
                }
            }
            .overlay(alignment: .topTrailing) {
                ClipboardScrollbarOverlay(scrollController: scrollController)
            }
            .opacity(isAwaitingInitialOpenScroll ? 0 : 1)
            .onPreferenceChange(ClipboardScrollTargetFramePreferenceKey.self, perform: onMeasuredTargetFrameChanged)
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                onMenuTrackingEnded()
            }
            .onAppear {
                onAppear(scrollProxy)
            }
        }
    }
}
