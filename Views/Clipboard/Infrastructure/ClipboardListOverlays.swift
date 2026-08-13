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

    var body: some View {
        ScrollControllerScrollbarOverlay(
            scrollController: scrollController,
            scrollbarWidth: ClipboardListStructure.LayoutMetrics.scrollbarWidth,
            contentPadding: ClipboardListStructure.LayoutMetrics.contentPadding
        )
    }
}
