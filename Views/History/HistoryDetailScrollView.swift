import SwiftUI

struct HistoryDetailScrollView<Content: View>: View {
    private let padding = CGFloat(8)
    private let paddingAdjustment = CGFloat(0.5)
    private let scrollbarWidth = CGFloat(4)

    @StateObject private var scrollController = ScrollController()
    @ViewBuilder let content: () -> Content

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        hasVisibleScrollbar ? scrollbarWidth + 2*padding + paddingAdjustment : padding
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
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
                            scrollView.verticalScrollElasticity = .none
                            scrollView.horizontalScrollElasticity = .none
                            scrollController.configure(scrollView: scrollView)
                        },
                        searchStrategy: .nearestAncestorOnly
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
        }
        .overlay(alignment: .topTrailing) {
            let viewportHeight = scrollController.viewportHeight
            let contentHeight = scrollController.contentHeight
            let trackHeight = max(0, viewportHeight - 2 * padding)
            let maxScrollOffset = max(0, contentHeight - viewportHeight)

            if trackHeight > 0, maxScrollOffset > 0 {
                ScrollbarThumbView(
                    viewportHeight: viewportHeight,
                    contentHeight: contentHeight,
                    scrollbarWidth: scrollbarWidth,
                    scrollOffset: scrollController.scrollOffset
                ) { progress in
                    scrollController.scroll(to: progress)
                }
                .frame(width: scrollbarWidth, height: trackHeight)
                .contentShape(Rectangle())
                .padding(.vertical, padding)
                .padding(.trailing, padding + paddingAdjustment)
                .zIndex(10)
            }
        }
    }
}
