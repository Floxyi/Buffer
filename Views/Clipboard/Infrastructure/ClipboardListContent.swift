import AppKit
import SwiftUI

struct ClipboardListContent: View {
    let scrollController: ScrollController
    @ObservedObject var scrollCoordinator: ClipboardListScrollCoordinator
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator
    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    let hoverCoordinator: ClipboardListHoverCoordinator

    let items: [ClipboardItem]
    let displayRowsForRendering: [ClipboardListStructure.DisplayRow]
    let contentTrailingPadding: CGFloat
    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let isAwaitingInitialOpenScroll: Bool
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
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
                        onCommitSelection: onCommitSelection,
                        onSelectSingle: onSelectSingle,
                        onToggleSelection: onToggleSelection,
                        onExtendSelectionTo: onExtendSelectionTo,
                        contextMenuActions: contextMenuActions,
                        onContextMenuAction: onContextMenuAction,
                        contextMenuState: contextMenuState,
                        measuredScrollCoordinator: measuredScrollCoordinator,
                        hoverCoordinator: hoverCoordinator,
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
