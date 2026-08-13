import AppKit
import SwiftUI

struct ScrollbarThumbView: NSViewRepresentable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let scrollbarWidth: CGFloat
    let scrollOffset: CGFloat
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollbarThumbInteractionView {
        let view = ScrollbarThumbInteractionView()
        view.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset,
            onScroll: onScroll
        )
        return view
    }

    func updateNSView(_ nsView: ScrollbarThumbInteractionView, context: Context) {
        nsView.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset,
            onScroll: onScroll
        )
    }
}

struct ScrollControllerScrollbarOverlay: View {
    let scrollController: ScrollController
    let scrollbarWidth: CGFloat
    let contentPadding: CGFloat

    @ObservedObject private var state: ScrollPresentationState

    init(
        scrollController: ScrollController,
        scrollbarWidth: CGFloat,
        contentPadding: CGFloat
    ) {
        self.scrollController = scrollController
        self.scrollbarWidth = scrollbarWidth
        self.contentPadding = contentPadding
        self._state = ObservedObject(wrappedValue: scrollController.presentationState)
    }

    var body: some View {
        let viewportHeight = state.viewportHeight
        let contentHeight = state.contentHeight
        let trackHeight = max(0, viewportHeight - 2 * contentPadding)
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollbarWidth: scrollbarWidth,
                scrollOffset: state.scrollOffset,
                onScroll: scrollController.scroll(to:)
            )
            .frame(width: scrollbarWidth, height: trackHeight)
            .contentShape(Rectangle())
            .padding(.vertical, contentPadding)
            .padding(.trailing, contentPadding)
            .zIndex(10)
        }
    }
}
