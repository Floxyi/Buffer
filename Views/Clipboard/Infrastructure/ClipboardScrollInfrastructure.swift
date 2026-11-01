import AppKit

@MainActor
final class ScrollPresentationState: ObservableObject {
    @Published private var metrics = SmoothWheelScroller.Metrics.zero

    var viewportHeight: CGFloat { metrics.viewportHeight }
    var contentHeight: CGFloat { metrics.contentHeight }
    var scrollOffset: CGFloat { metrics.scrollOffset }

    fileprivate func update(_ metrics: SmoothWheelScroller.Metrics) {
        self.metrics = metrics
    }
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
    var onUserScrollStarted: (() -> Void)?

    weak var scrollView: NSScrollView?

    private let metricsObserver = ScrollControllerMetricsObserver()
    private let smoothWheelScroller = SmoothWheelScroller()
    private let viewportLock = ScrollControllerViewportLock()

    deinit {
        MainActor.assumeIsolated {
            metricsObserver.removeObservers()
        }
    }

    func configure(scrollView: NSScrollView, interactionMode: InteractionMode = .smoothWheel) {
        self.scrollView = scrollView
        metricsObserver.configure(
            scrollView: scrollView,
            onUserInteractionStarted: { [weak self] in
                self?.handleUserScrollStarted()
            },
            onBoundsChanged: { [weak self] scrollView in
                self?.restoreLockedViewportIfNeeded(in: scrollView)
            },
            onSyncRequested: { [weak self] scrollView in
                self?.syncMetricsNow(from: scrollView)
            }
        )
        switch interactionMode {
        case .smoothWheel:
            smoothWheelScroller.configure(
                scrollView: scrollView,
                onScroll: { [weak self] targetOffset in
                    self?.handleUserScrollStarted()
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
        handleUserScrollStarted()
        guard let scrollView,
            let documentView = scrollView.documentView
        else {
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

    func beginViewportUpdate(at offset: CGFloat) {
        // A content mutation exclusively owns programmatic navigation until
        // its deterministic target is installed or native user input cancels it.
        viewportLock.lock(at: offset)
    }

    func cancelViewportUpdate() {
        viewportLock.unlock()
    }

    func completeViewportUpdate(at offset: CGFloat) {
        viewportLock.lock(at: offset)
        scrollToOffset(offset, duringViewportUpdate: true)
    }

    @discardableResult
    func scrollBy(deltaY: CGFloat) -> Bool {
        handleUserScrollStarted()
        guard abs(deltaY) > 0.5,
            let scrollView
        else {
            return false
        }

        let currentOffset = scrollView.contentView.bounds.minY
        scrollToOffset(currentOffset + deltaY)
        return abs(scrollView.contentView.bounds.minY - currentOffset) > 0.5
    }

    func scrollToTopImmediately() {
        scrollToOffset(0)
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

    func currentViewportHeightSnapshot() -> CGFloat {
        guard let scrollView else {
            return viewportHeight
        }

        return max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )
    }

    private func handleUserScrollStarted() {
        viewportLock.unlock()
        onUserScrollStarted?()
    }

    /// AppKit may clamp an `NSClipView` while SwiftUI replaces the document
    /// geometry. Bounds-change notifications arrive before the next display
    /// pass, so restoring the mutation-owned offset here keeps that transient
    /// clamp from ever becoming a visible frame.
    private func restoreLockedViewportIfNeeded(in scrollView: NSScrollView) {
        guard let lockedOffset = viewportLock.offset,
            !viewportLock.isRestoring,
            abs(scrollView.contentView.bounds.minY - lockedOffset) > 0.5
        else { return }

        viewportLock.withRestoration {
            let proposedOrigin = NSPoint(
                x: scrollView.contentView.bounds.minX,
                y: lockedOffset
            )
            scrollView.contentView.scroll(to: proposedOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func scrollToOffset(
        _ targetOffset: CGFloat,
        duringViewportUpdate: Bool = false
    ) {
        guard duringViewportUpdate || !viewportLock.isLocked else { return }
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
            didChange = true
        }

        if abs(contentHeight - nextContentHeight) > 0.5 {
            contentHeight = nextContentHeight
            didChange = true
        }

        if abs(scrollOffset - nextScrollOffset) > 0.5 {
            scrollOffset = nextScrollOffset
            activityTracker.markScrolling()
            didChange = true
        }

        if didChange {
            let metrics = metricsSnapshot()
            presentationState.update(metrics)
            onMetricsChanged?(metrics)
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

@MainActor
private final class ScrollControllerViewportLock {
    private(set) var offset: CGFloat?
    private(set) var isRestoring = false

    var isLocked: Bool { offset != nil }

    func lock(at offset: CGFloat) {
        self.offset = offset
    }

    func unlock() {
        offset = nil
    }

    func withRestoration(_ restore: () -> Void) {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }
        restore()
    }
}
