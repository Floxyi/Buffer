import AppKit
import QuartzCore

@MainActor
final class SmoothWheelScroller {
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
            let metrics
        else {
            return event
        }

        let currentMetrics = metrics()
        let maxOffset = max(0, currentMetrics.contentHeight - currentMetrics.viewportHeight)
        guard maxOffset > 0 else {
            return event
        }

        let startOffset =
            animationTask == nil
            ? currentMetrics.scrollOffset
            : animatedOffset.clamped(to: 0...maxOffset)
        let baseTargetOffset =
            animationTask == nil
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
        event.momentumPhase == [] && event.phase == [] && abs(event.scrollingDeltaY) > 0.01
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
