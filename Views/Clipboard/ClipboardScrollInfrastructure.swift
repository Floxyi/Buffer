import AppKit
import SwiftUI

@MainActor
final class ScrollActivityTracker: ObservableObject {
    @Published private(set) var isScrolling = false

    private var generation: UInt = 0
    private let idleDelayNanoseconds: UInt64 = 120_000_000

    func markScrolling() {
        generation &+= 1
        let currentGeneration = generation

        if !isScrolling {
            isScrolling = true
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: self.idleDelayNanoseconds)

            guard currentGeneration == self.generation else { return }

            self.isScrolling = false
        }
    }
}

@MainActor
final class ScrollController: ObservableObject {
    fileprivate enum SmoothScrollStyle {
        static let wheelStep = CGFloat(2)
        static let preciseWheelMultiplier = CGFloat(2)
        static let animationDuration = 0.32
        static let frameDurationNanoseconds: UInt64 = 1_000_000_000 / 60
    }

    @Published private(set) var viewportHeight: CGFloat = 0
    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var scrollOffset: CGFloat = 0

    let activityTracker = ScrollActivityTracker()

    weak var scrollView: NSScrollView?

    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var isMetricsSyncScheduled = false
    private let smoothWheelScroller = SmoothWheelScroller()

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
        }
    }

    func configure(scrollView: NSScrollView, enablesWheelSmoothing: Bool = true) {
        let documentViewChanged = observedDocumentView !== scrollView.documentView

        if self.scrollView === scrollView, !documentViewChanged {
            scheduleMetricsSync(from: scrollView)
            return
        }

        removeObservers()

        self.scrollView = scrollView
        observedDocumentView = scrollView.documentView

        startObserving(scrollView: scrollView)
        if enablesWheelSmoothing {
            smoothWheelScroller.configure(
                scrollView: scrollView,
                onScroll: { [weak self] targetOffset in
                    self?.scrollToOffset(targetOffset)
                },
                metrics: { [weak self] in
                    self?.metricsSnapshot() ?? .zero
                }
            )
        } else {
            smoothWheelScroller.disable()
        }
        scheduleMetricsSync(from: scrollView)
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
        scheduleScrollToTop(remainingPasses: retryCount)
    }

    func scrollToTopImmediately() {
        scrollToTopNow()
    }

    func scrollToBottom(retryCount: Int = 4) {
        scheduleScrollToBottom(remainingPasses: retryCount)
    }

    func scrollToBottomImmediately() {
        scrollToBottomNow()
    }

    func syncMetrics() {
        guard let scrollView else { return }
        scheduleMetricsSync(from: scrollView)
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

    private func scheduleScrollToTop(remainingPasses: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()

            self.scrollToTopNow()

            if remainingPasses > 0 {
                self.scheduleScrollToTop(remainingPasses: remainingPasses - 1)
            }
        }
    }

    private func scheduleScrollToBottom(remainingPasses: Int) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()

            self.scrollToBottomNow()

            if remainingPasses > 0 {
                self.scheduleScrollToBottom(remainingPasses: remainingPasses - 1)
            }
        }
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

    private func startObserving(scrollView: NSScrollView) {
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                MainActor.assumeIsolated {
                    self.scheduleMetricsSync(from: scrollView)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                MainActor.assumeIsolated {
                    self.scheduleMetricsSync(from: scrollView)
                }
            }
        )

        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            documentView.postsBoundsChangedNotifications = true

            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView else { return }
                    MainActor.assumeIsolated {
                        self.scheduleMetricsSync(from: scrollView)
                    }
                }
            )
        }
    }

    private func scheduleMetricsSync(from scrollView: NSScrollView) {
        guard !isMetricsSyncScheduled else { return }

        isMetricsSyncScheduled = true

        Task { @MainActor [weak self, weak scrollView] in
            guard let self else { return }
            await Task.yield()

            self.isMetricsSyncScheduled = false

            guard let scrollView else { return }

            self.syncMetricsNow(from: scrollView)
        }
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
        if abs(viewportHeight - nextViewportHeight) > 0.5 {
            viewportHeight = nextViewportHeight
        }

        if abs(contentHeight - nextContentHeight) > 0.5 {
            contentHeight = nextContentHeight
        }

        if abs(scrollOffset - nextScrollOffset) > 0.5 {
            scrollOffset = nextScrollOffset
            activityTracker.markScrolling()
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    private func metricsSnapshot() -> SmoothWheelScroller.Metrics {
        SmoothWheelScroller.Metrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollOffset: scrollOffset
        )
    }
}

@MainActor
private final class SmoothWheelScroller {
    struct Metrics {
        let viewportHeight: CGFloat
        let contentHeight: CGFloat
        let scrollOffset: CGFloat

        static let zero = Metrics(viewportHeight: 0, contentHeight: 0, scrollOffset: 0)
    }

    private weak var scrollView: NSScrollView?
    private var onScroll: ((CGFloat) -> Void)?
    private var metrics: (() -> Metrics)?
    nonisolated(unsafe) private var monitor: Any?
    nonisolated(unsafe) private var animationTask: Task<Void, Never>?
    private var animationID: UInt = 0
    private var animatedOffset = CGFloat.zero
    private var targetOffset = CGFloat.zero

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        animationTask?.cancel()
    }

    func configure(
        scrollView: NSScrollView,
        onScroll: @escaping (CGFloat) -> Void,
        metrics: @escaping () -> Metrics
    ) {
        self.scrollView = scrollView
        self.onScroll = onScroll
        self.metrics = metrics
        targetOffset = metrics().scrollOffset
        animatedOffset = targetOffset

        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollWheel(event)
        }
    }

    func disable() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        animationTask?.cancel()
        animationTask = nil
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard shouldSmooth(event: event),
              let scrollView,
              isPointerInsideScrollView(event: event, scrollView: scrollView),
              let onScroll,
              let metrics else {
            return event
        }

        let currentMetrics = metrics()
        let maxOffset = max(0, currentMetrics.contentHeight - currentMetrics.viewportHeight)
        guard maxOffset > 0 else {
            return event
        }

        let startOffset = animationTask == nil
            ? currentMetrics.scrollOffset
            : animatedOffset.clamped(to: 0...maxOffset)
        let baseTargetOffset = animationTask == nil
            ? currentMetrics.scrollOffset
            : targetOffset.clamped(to: 0...maxOffset)

        animationTask?.cancel()
        animationID &+= 1
        let currentAnimationID = animationID

        let delta = scrollDelta(for: event)
        targetOffset = (baseTargetOffset + delta)
            .clamped(to: 0...maxOffset)
        animatedOffset = startOffset

        animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.animate(
                id: currentAnimationID,
                from: startOffset,
                to: self.targetOffset,
                onScroll: onScroll
            )
        }

        return nil
    }

    private func shouldSmooth(event: NSEvent) -> Bool {
        event.momentumPhase == [] &&
        event.phase == [] &&
        abs(event.scrollingDeltaY) > 0.01
    }

    private func scrollDelta(for event: NSEvent) -> CGFloat {
        let baseDelta = -event.scrollingDeltaY

        if event.hasPreciseScrollingDeltas {
            return baseDelta * ScrollController.SmoothScrollStyle.preciseWheelMultiplier
        }

        return baseDelta * ScrollController.SmoothScrollStyle.wheelStep
    }

    private func isPointerInsideScrollView(event: NSEvent, scrollView: NSScrollView) -> Bool {
        guard let windowContentView = event.window?.contentView else {
            let point = scrollView.convert(event.locationInWindow, from: nil)
            return scrollView.bounds.contains(point)
        }

        let location = windowContentView.convert(event.locationInWindow, from: nil)
        guard let hitView = windowContentView.hitTest(location) else {
            return false
        }

        if hitView.isDescendant(of: scrollView) {
            return true
        }

        let point = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(point)
    }

    private func animate(
        id: UInt,
        from startOffset: CGFloat,
        to endOffset: CGFloat,
        onScroll: @escaping (CGFloat) -> Void
    ) async {
        guard abs(endOffset - startOffset) > 0.5 else {
            guard !Task.isCancelled, id == animationID else { return }
            animatedOffset = endOffset
            onScroll(endOffset)
            animationTask = nil
            return
        }

        let duration = ScrollController.SmoothScrollStyle.animationDuration
        let startDate = CACurrentMediaTime()

        while !Task.isCancelled {
            let elapsed = CACurrentMediaTime() - startDate
            let progress = min(1, elapsed / duration)
            let easedProgress = smoothStep(progress)
            let offset = startOffset + (endOffset - startOffset) * easedProgress
            animatedOffset = offset
            onScroll(offset)

            if progress >= 1 {
                break
            }

            try? await Task.sleep(nanoseconds: ScrollController.SmoothScrollStyle.frameDurationNanoseconds)
        }

        guard !Task.isCancelled, id == animationID else { return }
        animatedOffset = endOffset
        onScroll(endOffset)
        animationTask = nil
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clampedValue = value.clamped(to: 0...1)
        let easedValue = clampedValue * clampedValue * (3 - 2 * clampedValue)
        return CGFloat(easedValue)
    }
}
