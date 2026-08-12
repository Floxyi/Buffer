import AppKit
import SwiftUI

struct ClipboardListContent: View {
    let scrollController: ScrollController
    @ObservedObject var scrollCoordinator: ClipboardListScrollCoordinator
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator
    @ObservedObject var contextMenuState: ClipboardListContextMenuState

    let items: [ClipboardItem]
    let displayRowsForRendering: [ClipboardListStructure.DisplayRow]
    let contentTrailingPadding: CGFloat
    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let hoveredItemID: UUID?
    let isAwaitingInitialOpenScroll: Bool
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onHoveredItemIDChanged: (UUID?) -> Void
    let onSelectedIndexChanged: (Int) -> Void
    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int
    let onScrollViewReady: (NSScrollView) -> Void
    let onScrollToTopRequested: (ScrollViewProxy) -> Void
    let onMeasuredTargetFrameChanged: (CGRect?) -> Void
    let onMenuTrackingEnded: () -> Void
    let onAppear: (ScrollViewProxy) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: ClipboardListStructure.LayoutMetrics.rowSpacing) {
                    ClipboardListRowsSection(
                        rows: displayRowsForRendering,
                        items: items,
                        store: store,
                        settings: settings,
                        quickPasteBadgeNumberByItemID: quickPasteBadgeNumberByItemID,
                        selectedIDs: selectedIDs,
                        hoveredItemID: hoveredItemID,
                        onCommitSelection: onCommitSelection,
                        onSelectSingle: onSelectSingle,
                        onToggleSelection: onToggleSelection,
                        onExtendSelectionTo: onExtendSelectionTo,
                        contextMenuActions: contextMenuActions,
                        onContextMenuAction: onContextMenuAction,
                        onHoveredItemIDChanged: onHoveredItemIDChanged,
                        onSelectedIndexChanged: onSelectedIndexChanged,
                        scrollController: scrollController,
                        contextMenuState: contextMenuState,
                        measuredScrollCoordinator: measuredScrollCoordinator,
                        primaryLabelText: primaryLabelText,
                        indexForItem: indexForItem
                    )
                }
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
                    onHoveredItemIDChanged(nil)
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
