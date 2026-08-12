import SwiftUI

struct ClipboardScrollToTopOverlay: View {
    let scrollController: ScrollController
    @ObservedObject private var state: ScrollPresentationState
    let onSelectTop: () -> Void

    init(scrollController: ScrollController, onSelectTop: @escaping () -> Void) {
        self.scrollController = scrollController
        self._state = ObservedObject(wrappedValue: scrollController.presentationState)
        self.onSelectTop = onSelectTop
    }

    var body: some View {
        let viewportHeight = state.viewportHeight
        let scrollOffset = state.scrollOffset

        if scrollOffset > max(80, viewportHeight * 0.35) {
            ClipboardScrollToTopButton {
                onSelectTop()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ClipboardScrollbarOverlay: View {
    let scrollController: ScrollController
    @ObservedObject private var state: ScrollPresentationState

    init(scrollController: ScrollController) {
        self.scrollController = scrollController
        self._state = ObservedObject(wrappedValue: scrollController.presentationState)
    }

    var body: some View {
        let viewportHeight = state.viewportHeight
        let contentHeight = state.contentHeight

        let trackHeight = max(
            0,
            viewportHeight - 2 * ClipboardListStructure.LayoutMetrics.contentPadding
        )
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollbarWidth: ClipboardListStructure.LayoutMetrics.scrollbarWidth,
                scrollOffset: state.scrollOffset
            ) { progress in
                scrollController.scroll(to: progress)
            }
            .frame(
                width: ClipboardListStructure.LayoutMetrics.scrollbarWidth,
                height: trackHeight
            )
            .contentShape(Rectangle())
            .padding(.vertical, ClipboardListStructure.LayoutMetrics.contentPadding)
            .padding(.trailing, ClipboardListStructure.LayoutMetrics.contentPadding)
            .zIndex(10)
        }
    }
}
