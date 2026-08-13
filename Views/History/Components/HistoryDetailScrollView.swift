import Foundation
import SwiftUI

struct HistoryDetailScrollResetID: Equatable {
    let focusedItemID: UUID?
    let selectedItemIDs: [UUID]

    init(detailState: HistoryDetailViewState) {
        focusedItemID = detailState.selectedItem?.id
        selectedItemIDs = detailState.selectedItems.map(\.id)
    }
}

struct HistoryDetailScrollView<Content: View>: View {
    private let padding = CGFloat(8)
    private let paddingAdjustment = CGFloat(0.5)
    private let scrollbarWidth = CGFloat(4)

    @StateObject private var scrollController = ScrollController()
    let resetID: HistoryDetailScrollResetID
    @ViewBuilder let content: () -> Content

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        hasVisibleScrollbar ? scrollbarWidth + 2*padding + paddingAdjustment : padding
    }

    var body: some View {
        let minimumContentHeight = max(0, scrollController.viewportHeight - 2 * padding)

        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, minHeight: minimumContentHeight, alignment: .top)
                .padding(.vertical, padding)
                .padding(.leading, padding)
                .padding(.trailing, contentTrailingPadding)
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
                scrollbarWidth: scrollbarWidth,
                contentPadding: padding
            )
        }
    }
}
