import Foundation
import SwiftUI

enum HistoryDetailViewportMode: Equatable {
    case fitted
    case scrollable

    init(selectionCount: Int, selectedItem: ClipboardItem?) {
        if selectionCount == 1,
           let selectedItem,
           selectedItem.kind == .link {
            self = .fitted
        } else {
            self = .scrollable
        }
    }
}

private enum HistoryDetailLayout {
    static let contentPadding = CGFloat(8)
    static let paddingAdjustment = CGFloat(0.5)
    static let scrollbarWidth = CGFloat(4)

    static var contentTrailingPadding: CGFloat {
        scrollbarWidth + 2 * contentPadding + paddingAdjustment
    }

    static var scrollableContentInsets: EdgeInsets {
        EdgeInsets(
            top: contentPadding,
            leading: contentPadding,
            bottom: contentPadding,
            trailing: contentTrailingPadding
        )
    }
}

struct HistoryDetailScrollResetID: Equatable {
    let focusedItemID: UUID?
    let selectedItemIDs: [UUID]

    init(detailState: HistoryDetailViewState) {
        focusedItemID = detailState.selectedItem?.id
        selectedItemIDs = detailState.selectedItems.map(\.id)
    }
}

struct HistoryDetailScrollView<Content: View>: View {
    @StateObject private var scrollController = ScrollController()
    let resetID: HistoryDetailScrollResetID
    @ViewBuilder let content: () -> Content

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    var body: some View {
        let minimumContentHeight = max(
            0,
            scrollController.viewportHeight - 2 * HistoryDetailLayout.contentPadding
        )

        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, minHeight: minimumContentHeight, alignment: .top)
                // Always reserve scrollbar space. Conditional insets change the
                // wrapping width after overflow has already been measured.
                .padding(HistoryDetailLayout.scrollableContentInsets)
                .background {
                    ScrollViewConfigurator(
                        configure: { scrollView in
                            scrollView.hasVerticalScroller = false
                            scrollView.autohidesScrollers = true
                            scrollView.scrollerStyle = .overlay
                            scrollView.automaticallyAdjustsContentInsets = false
                            scrollView.verticalScrollElasticity = hasVisibleScrollbar ? .automatic : .none
                            scrollView.horizontalScrollElasticity = .none
                            scrollController.configure(
                                scrollView: scrollView,
                                interactionMode: .system
                            )
                        },
                        searchStrategy: .nearestAncestorOnly
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
        }
        .onChange(of: resetID) { _ in
            scrollController.scrollToTopImmediately()
        }
        .overlay(alignment: .topTrailing) {
            ScrollControllerScrollbarOverlay(
                scrollController: scrollController,
                scrollbarWidth: HistoryDetailLayout.scrollbarWidth,
                contentPadding: HistoryDetailLayout.contentPadding
            )
        }
    }
}

struct HistoryDetailFittedView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .padding(HistoryDetailLayout.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}
