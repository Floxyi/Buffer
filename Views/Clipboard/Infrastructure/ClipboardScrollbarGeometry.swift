import AppKit

struct ScrollbarMetrics {
    let thumbRect: NSRect
    let availableTravel: CGFloat

    static func make(
        trackHeight: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        scrollOffset: CGFloat,
        dragProgress: CGFloat?
    ) -> ScrollbarMetrics {
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        guard trackHeight > 0, maxScrollOffset > 0 else {
            return ScrollbarMetrics(
                thumbRect: .zero,
                availableTravel: 0
            )
        }

        let visibleRatio = viewportHeight / max(contentHeight, viewportHeight)
        let thumbHeight = min(trackHeight, max(40, trackHeight * visibleRatio))
        let availableTravel = max(0, trackHeight - thumbHeight)

        let progress: CGFloat

        if let dragProgress {
            progress = dragProgress.clamped(to: 0...1)
        } else {
            progress =
                maxScrollOffset > 0
                ? (scrollOffset / maxScrollOffset).clamped(to: 0...1)
                : 0
        }

        let thumbOrigin = availableTravel * progress

        return ScrollbarMetrics(
            thumbRect: NSRect(
                x: 0,
                y: thumbOrigin,
                width: 1,
                height: thumbHeight
            ),
            availableTravel: availableTravel
        )
    }
}
