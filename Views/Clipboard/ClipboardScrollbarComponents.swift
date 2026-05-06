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
