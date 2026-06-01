import AppKit
import SwiftUI

struct ScrollbarThumbView: NSViewRepresentable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let scrollbarWidth: CGFloat
    let scrollOffset: CGFloat
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ScrollbarThumbInteractionView {
        let view = ScrollbarThumbInteractionView()
        context.coordinator.updateStoredMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset
        )
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
        guard context.coordinator.shouldUpdate(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset
        ) else {
            return
        }

        context.coordinator.updateStoredMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset
        )

        nsView.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset,
            onScroll: onScroll
        )
    }

    final class Coordinator {
        private var previousViewportHeight = CGFloat.nan
        private var previousContentHeight = CGFloat.nan
        private var previousScrollbarWidth = CGFloat.nan
        private var previousScrollOffset = CGFloat.nan

        func shouldUpdate(
            viewportHeight: CGFloat,
            contentHeight: CGFloat,
            scrollbarWidth: CGFloat,
            scrollOffset: CGFloat
        ) -> Bool {
            abs(previousViewportHeight - viewportHeight) > 0.5 ||
            abs(previousContentHeight - contentHeight) > 0.5 ||
            abs(previousScrollbarWidth - scrollbarWidth) > 0.5 ||
            abs(previousScrollOffset - scrollOffset) > 1.5
        }

        func updateStoredMetrics(
            viewportHeight: CGFloat,
            contentHeight: CGFloat,
            scrollbarWidth: CGFloat,
            scrollOffset: CGFloat
        ) {
            previousViewportHeight = viewportHeight
            previousContentHeight = contentHeight
            previousScrollbarWidth = scrollbarWidth
            previousScrollOffset = scrollOffset
        }
    }
}
