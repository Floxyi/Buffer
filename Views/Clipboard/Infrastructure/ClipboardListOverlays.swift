import SwiftUI

struct ClipboardScrollToTopVisibilityPolicy: Equatable, Sendable {
    static let standard = ClipboardScrollToTopVisibilityPolicy(
        minimumItemsAboveViewport: 8
    )

    let minimumItemsAboveViewport: Int

    func shouldShow(itemCountAboveViewport: Int) -> Bool {
        itemCountAboveViewport >= max(1, minimumItemsAboveViewport)
    }
}

struct ClipboardScrollToTopOverlay: View {
    let scrollController: ScrollController
    let layoutIndex: ClipboardListLayoutIndex
    var visibilityPolicy = ClipboardScrollToTopVisibilityPolicy.standard
    @ObservedObject private var state: ScrollPresentationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelectTop: () -> Void

    init(
        scrollController: ScrollController,
        layoutIndex: ClipboardListLayoutIndex,
        visibilityPolicy: ClipboardScrollToTopVisibilityPolicy = .standard,
        onSelectTop: @escaping () -> Void
    ) {
        self.scrollController = scrollController
        self.layoutIndex = layoutIndex
        self.visibilityPolicy = visibilityPolicy
        self._state = ObservedObject(wrappedValue: scrollController.presentationState)
        self.onSelectTop = onSelectTop
    }

    var body: some View {
        let isVisible = visibilityPolicy.shouldShow(
            itemCountAboveViewport: layoutIndex.itemCountAboveViewport(
                scrollOffset: state.scrollOffset
            )
        )

        ZStack(alignment: .top) {
            if isVisible {
                ClipboardScrollToTopButton(action: onSelectTop)
                    .padding(.top, 12)
                    .transition(buttonTransition)
            }
        }
        .animation(buttonAnimation, value: isVisible)
    }

    private var buttonTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -8))
                .combined(with: .scale(scale: 0.94, anchor: .top)),
            removal: .opacity.combined(with: .offset(y: -4))
        )
    }

    private var buttonAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .snappy(duration: 0.2, extraBounce: 0)
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
