import AppKit

@MainActor
final class ScrollPresentationState: ObservableObject {
    @Published fileprivate(set) var viewportHeight: CGFloat = 0
    @Published fileprivate(set) var contentHeight: CGFloat = 0
    @Published fileprivate(set) var scrollOffset: CGFloat = 0
}

@MainActor
final class ScrollController: ObservableObject {
    enum InteractionMode {
        case system
        case smoothWheel
    }

    enum SmoothScrollStyle {
        static let wheelStep = CGFloat(2)
        static let preciseWheelMultiplier = CGFloat(2)
        static let animationDuration = 0.32
        static let frameDurationNanoseconds: UInt64 = 1_000_000_000 / 60
    }

    @Published private(set) var viewportHeight: CGFloat = 0
    @Published private(set) var contentHeight: CGFloat = 0
    private(set) var scrollOffset: CGFloat = 0

    let activityTracker = ScrollActivityTracker()
    let presentationState = ScrollPresentationState()
    var onMetricsChanged: ((SmoothWheelScroller.Metrics) -> Void)?

    weak var scrollView: NSScrollView?

    private let metricsObserver = ScrollControllerMetricsObserver()
    private let settledScrollScheduler = ScrollControllerSettledScrollScheduler()
    private let smoothWheelScroller = SmoothWheelScroller()

    deinit {
        MainActor.assumeIsolated {
            metricsObserver.removeObservers()
            settledScrollScheduler.cancel()
        }
    }

    func configure(scrollView: NSScrollView, interactionMode: InteractionMode = .smoothWheel) {
        self.scrollView = scrollView
        metricsObserver.configure(
            scrollView: scrollView,
            onSyncRequested: { [weak self] scrollView in
                self?.syncMetricsNow(from: scrollView)
            }
        )
        switch interactionMode {
        case .smoothWheel:
            smoothWheelScroller.configure(
                scrollView: scrollView,
                onScroll: { [weak self] targetOffset in
                    self?.scrollToOffset(targetOffset)
                },
                metrics: { [weak self] in
                    self?.metricsSnapshot() ?? .zero
                }
            )
        case .system:
            smoothWheelScroller.disable()
        }
    }

    func scroll(to progress: CGFloat) {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return
        }

        let clampedProgress = progress.clamped(to: 0...1)

        let viewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )

        let contentHeight = measuredContentHeight(
            scrollView: scrollView,
            documentView: documentView
        )

        let maxOffset = max(0, contentHeight - viewportHeight)
        let targetY = maxOffset * clampedProgress

        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: targetY.clamped(to: 0...maxOffset),
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)

        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        syncMetricsNow(from: scrollView)
    }

    func scrollTo(offset: CGFloat) {
        scrollToOffset(offset)
    }

    func settleScroll(to offset: CGFloat, retryCount: Int = 4) {
        settledScrollScheduler.schedule(retryCount: retryCount) { [weak self] in
            self?.scrollToOffset(offset)
        }
    }

    func scrollBy(deltaY: CGFloat) {
        guard abs(deltaY) > 0.5,
              let scrollView else {
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()

        let currentOffset = scrollView.contentView.bounds.minY
        scrollToOffset(currentOffset + deltaY)
    }

    func scrollToTop(retryCount: Int = 4) {
        settledScrollScheduler.schedule(retryCount: retryCount) { [weak self] in
            self?.scrollToTopNow()
        }
    }

    func scrollToTopImmediately() {
        scrollToTopNow()
    }

    func scrollToBottom(retryCount: Int = 4) {
        settledScrollScheduler.schedule(retryCount: retryCount) { [weak self] in
            self?.scrollToBottomNow()
        }
    }

    func scrollToBottomImmediately() {
        scrollToBottomNow()
    }

    func syncMetrics() {
        guard let scrollView else { return }
        metricsObserver.scheduleSync(
            for: scrollView,
            onSyncRequested: { [weak self] scrollView in
                self?.syncMetricsNow(from: scrollView)
            }
        )
    }

    func syncMetricsImmediately() {
        guard let scrollView else { return }

        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()
        syncMetricsNow(from: scrollView)
    }

    func currentScrollOffsetSnapshot() -> CGFloat {
        guard let scrollView else {
            return scrollOffset
        }

        let viewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )
        let contentHeight: CGFloat
        if let documentView = scrollView.documentView {
            contentHeight = measuredContentHeight(
                scrollView: scrollView,
                documentView: documentView
            )
        } else {
            contentHeight = self.contentHeight
        }

        let maxOffset = max(0, contentHeight - viewportHeight)
        return scrollView.contentView.bounds.minY.clamped(to: 0...maxOffset)
    }

    private func scrollToTopNow() {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: 0,
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)

        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        syncMetricsNow(from: scrollView)
    }

    private func scrollToBottomNow() {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let viewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )
        let contentHeight = measuredContentHeight(
            scrollView: scrollView,
            documentView: documentView
        )
        let maxOffset = max(0, contentHeight - viewportHeight)

        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: maxOffset,
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)

        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        syncMetricsNow(from: scrollView)
    }

    private func scrollToOffset(_ targetOffset: CGFloat) {
        guard let scrollView else {
            return
        }

        let viewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )
        let contentHeight: CGFloat
        if let documentView = scrollView.documentView {
            contentHeight = measuredContentHeight(
                scrollView: scrollView,
                documentView: documentView
            )
        } else {
            contentHeight = self.contentHeight
        }

        let maxOffset = max(0, contentHeight - viewportHeight)
        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: targetOffset.clamped(to: 0...maxOffset),
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)
        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        syncMetricsNow(from: scrollView)
    }

    private func syncMetricsNow(from scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else {
            update(
                viewportHeight: 0,
                contentHeight: 0,
                scrollOffset: 0
            )
            return
        }

        let nextViewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )

        let nextContentHeight = measuredContentHeight(
            scrollView: scrollView,
            documentView: documentView
        )

        let maxOffset = max(0, nextContentHeight - nextViewportHeight)
        let rawY = scrollView.contentView.bounds.minY
        let nextScrollOffset = rawY.clamped(to: 0...maxOffset)

        update(
            viewportHeight: nextViewportHeight,
            contentHeight: nextContentHeight,
            scrollOffset: nextScrollOffset
        )
    }

    private func measuredContentHeight(
        scrollView: NSScrollView,
        documentView: NSView
    ) -> CGFloat {
        max(
            documentView.bounds.height,
            documentView.frame.height,
            scrollView.contentView.documentRect.height
        )
    }

    private func update(
        viewportHeight nextViewportHeight: CGFloat,
        contentHeight nextContentHeight: CGFloat,
        scrollOffset nextScrollOffset: CGFloat
    ) {
        var didChange = false
        if abs(viewportHeight - nextViewportHeight) > 0.5 {
            viewportHeight = nextViewportHeight
            presentationState.viewportHeight = nextViewportHeight
            didChange = true
        }

        if abs(contentHeight - nextContentHeight) > 0.5 {
            contentHeight = nextContentHeight
            presentationState.contentHeight = nextContentHeight
            didChange = true
        }

        if abs(scrollOffset - nextScrollOffset) > 0.5 {
            scrollOffset = nextScrollOffset
            presentationState.scrollOffset = nextScrollOffset
            activityTracker.markScrolling()
            didChange = true
        }

        if didChange {
            onMetricsChanged?(metricsSnapshot())
        }
    }

    private func metricsSnapshot() -> SmoothWheelScroller.Metrics {
        SmoothWheelScroller.Metrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollOffset: scrollOffset
        )
    }

    func currentMetrics() -> SmoothWheelScroller.Metrics {
        metricsSnapshot()
    }
}
