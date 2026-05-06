import AppKit

struct ScrollbarThumbLayerModel {
    let frame: CGRect
    let cornerRadius: CGFloat
    let alpha: CGFloat
    let isHidden: Bool
}

struct ScrollbarThumbInteractionState {
    var viewportHeight: CGFloat = 0
    var contentHeight: CGFloat = 0
    var scrollbarWidth: CGFloat = 4
    var scrollOffset: CGFloat = 0

    var isHovering = false
    var isDraggingThumb = false

    var dragOffsetWithinThumb: CGFloat = 0
    var dragProgress: CGFloat?

    var dragViewportHeight: CGFloat?
    var dragContentHeight: CGFloat?

    var collapsedWidth: CGFloat {
        max(2, scrollbarWidth)
    }

    var expandedWidth: CGFloat {
        max(2, scrollbarWidth + scrollbarWidth / 3)
    }

    mutating func updateMetrics(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        scrollbarWidth: CGFloat,
        scrollOffset: CGFloat
    ) -> Bool {
        let previousViewportHeight = self.viewportHeight
        let previousContentHeight = self.contentHeight
        let previousScrollOffset = self.scrollOffset
        let hadValidMetrics = previousViewportHeight > 0 && previousContentHeight > 0

        self.scrollbarWidth = max(2, scrollbarWidth)

        guard !isDraggingThumb else {
            return false
        }

        self.viewportHeight = viewportHeight
        self.contentHeight = contentHeight
        self.scrollOffset = scrollOffset
        self.dragProgress = nil
        self.dragViewportHeight = nil
        self.dragContentHeight = nil

        let didScroll = abs(previousScrollOffset - scrollOffset) > 0.5
        let didResize =
            abs(previousViewportHeight - viewportHeight) > 0.5 ||
            abs(previousContentHeight - contentHeight) > 0.5

        return hadValidMetrics && (didScroll || didResize)
    }

    mutating func beginHover() {
        isHovering = true
    }

    mutating func endHover() {
        guard !isDraggingThumb else { return }
        isHovering = false
    }

    mutating func beginDrag(mouseY: CGFloat, trackHeight: CGFloat) -> CGFloat? {
        dragViewportHeight = viewportHeight
        dragContentHeight = contentHeight

        let metrics = scrollbarMetrics(trackHeight: trackHeight)
        let thumbRect = metrics.thumbRect

        guard thumbRect.height > 0 else { return nil }

        if thumbRect.contains(NSPoint(x: 0, y: mouseY)) {
            dragOffsetWithinThumb = mouseY - thumbRect.minY
        } else {
            dragOffsetWithinThumb = thumbRect.height / 2
        }

        isDraggingThumb = true

        guard !thumbRect.contains(NSPoint(x: 0, y: mouseY)) else {
            return nil
        }

        return scroll(toThumbOrigin: mouseY - dragOffsetWithinThumb, metrics: metrics)
    }

    mutating func drag(mouseY: CGFloat, trackHeight: CGFloat) -> CGFloat? {
        guard isDraggingThumb else { return nil }
        return scroll(
            toThumbOrigin: mouseY - dragOffsetWithinThumb,
            metrics: scrollbarMetrics(trackHeight: trackHeight)
        )
    }

    mutating func endDrag(mouseY: CGFloat, boundsHeight: CGFloat) {
        isDraggingThumb = false
        dragProgress = nil
        dragViewportHeight = nil
        dragContentHeight = nil
        isHovering = (0...boundsHeight).contains(mouseY)
    }

    func layerModel(for trackBounds: CGRect) -> ScrollbarThumbLayerModel {
        let metrics = scrollbarMetrics(trackHeight: trackBounds.height)
        let thumbRect = metrics.thumbRect

        guard thumbRect.height > 0 else {
            return ScrollbarThumbLayerModel(
                frame: .zero,
                cornerRadius: 0,
                alpha: 0,
                isHidden: true
            )
        }

        let visualWidth = isHovering || isDraggingThumb
            ? expandedWidth
            : collapsedWidth

        let alpha: CGFloat

        if isDraggingThumb {
            alpha = 0.46
        } else if isHovering {
            alpha = 0.34
        } else {
            alpha = 0.22
        }

        return ScrollbarThumbLayerModel(
            frame: CGRect(
                x: (trackBounds.width - visualWidth) / 2,
                y: thumbRect.minY,
                width: visualWidth,
                height: thumbRect.height
            ),
            cornerRadius: visualWidth / 2,
            alpha: alpha,
            isHidden: false
        )
    }

    private mutating func scroll(
        toThumbOrigin originY: CGFloat,
        metrics: ScrollbarMetrics
    ) -> CGFloat {
        let clampedOrigin = originY.clamped(to: 0...metrics.availableTravel)
        let progress = metrics.availableTravel > 0
            ? clampedOrigin / metrics.availableTravel
            : 0

        let activeViewportHeight = dragViewportHeight ?? viewportHeight
        let activeContentHeight = dragContentHeight ?? contentHeight
        let maxScrollOffset = max(0, activeContentHeight - activeViewportHeight)

        dragProgress = progress
        scrollOffset = maxScrollOffset * progress

        return progress
    }

    private func scrollbarMetrics(trackHeight: CGFloat) -> ScrollbarMetrics {
        ScrollbarMetrics.make(
            trackHeight: trackHeight,
            viewportHeight: dragViewportHeight ?? viewportHeight,
            contentHeight: dragContentHeight ?? contentHeight,
            scrollOffset: scrollOffset,
            dragProgress: dragProgress
        )
    }
}
