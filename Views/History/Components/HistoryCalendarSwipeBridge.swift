import AppKit
import SwiftUI

enum HistoryCalendarSwipeDirection: Equatable, Sendable {
    case previous
    case next

    var monthDelta: Int {
        switch self {
        case .previous: -1
        case .next: 1
        }
    }

    var settledProgress: CGFloat {
        switch self {
        case .previous: 1
        case .next: -1
        }
    }
}

struct HistoryCalendarSwipeLimits: Equatable, Sendable {
    let minimumProgress: CGFloat
    let maximumProgress: CGFloat
}

enum HistoryCalendarSwipePolicy {
    private static let minimumHorizontalDelta = CGFloat(0.01)
    // Initial trackpad packets are often slightly diagonal before the intent settles.
    private static let minimumHorizontalIntentRatio = CGFloat(0.35)
    private static let completionTolerance = CGFloat(0.01)
    // Firefox uses a 25% positional threshold plus projected release velocity.
    // The calendar page is much narrower than a browser viewport, so 22% keeps
    // deliberate drags predictable while still allowing short, quick flicks.
    private static let releaseCommitThreshold = CGFloat(0.22)
    private static let velocityProjectionDuration = CGFloat(0.12)
    private static let reverseVelocityTolerance = CGFloat(0.08)

    static func shouldBegin(
        swipeTrackingIsEnabled: Bool,
        hasPreciseScrollingDeltas: Bool,
        isBeginning: Bool,
        horizontalDelta: CGFloat,
        verticalDelta: CGFloat
    ) -> Bool {
        let horizontalMagnitude = abs(horizontalDelta)
        let verticalMagnitude = abs(verticalDelta)
        return swipeTrackingIsEnabled
            && hasPreciseScrollingDeltas
            && isBeginning
            && horizontalMagnitude > minimumHorizontalDelta
            && horizontalMagnitude >= verticalMagnitude * minimumHorizontalIntentRatio
    }

    static func limits(
        canNavigateBackward: Bool,
        canNavigateForward: Bool
    ) -> HistoryCalendarSwipeLimits {
        HistoryCalendarSwipeLimits(
            minimumProgress: canNavigateForward ? -1 : 0,
            maximumProgress: canNavigateBackward ? 1 : 0
        )
    }

    static func normalizedProgress(_ progress: CGFloat) -> CGFloat {
        progress.clamped(to: -1...1)
    }

    static func completedDirection(for progress: CGFloat) -> HistoryCalendarSwipeDirection? {
        if progress <= -1 + completionTolerance {
            return .next
        }
        if progress >= 1 - completionTolerance {
            return .previous
        }
        return nil
    }

    static func releasedDirection(
        for progress: CGFloat,
        velocity: CGFloat,
        canNavigateBackward: Bool,
        canNavigateForward: Bool
    ) -> HistoryCalendarSwipeDirection? {
        let targetProgress: CGFloat
        let direction: HistoryCalendarSwipeDirection
        if progress < 0 || (progress == 0 && velocity < 0) {
            targetProgress = -1
            direction = .next
        } else if progress > 0 || velocity > 0 {
            targetProgress = 1
            direction = .previous
        } else {
            return nil
        }

        let directionIsAvailable =
            switch direction {
            case .previous: canNavigateBackward
            case .next: canNavigateForward
            }
        guard directionIsAvailable else { return nil }

        // Releasing while already moving back toward the current month should
        // cancel, even if the page briefly crossed the positional threshold.
        guard velocity * targetProgress >= -reverseVelocityTolerance else {
            return nil
        }

        let projectedProgress =
            progress * targetProgress
            + velocity * targetProgress * velocityProjectionDuration
        return projectedProgress >= releaseCommitThreshold ? direction : nil
    }

    static func settlementDuration(from progress: CGFloat, to target: CGFloat) -> TimeInterval {
        let remainingDistance = min(1, abs(target - progress))
        return 0.06 + 0.05 * TimeInterval(remainingDistance)
    }
}

struct HistoryCalendarSwipeBridge: NSViewRepresentable {
    let isEnabled: Bool
    let canNavigateBackward: Bool
    let canNavigateForward: Bool
    let onBegan: @MainActor () -> Void
    let onProgress: @MainActor (CGFloat) -> Void
    let onReleased: @MainActor (HistoryCalendarSwipeDirection?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> HistoryCalendarSwipeTrackingView {
        let view = HistoryCalendarSwipeTrackingView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(
        _ nsView: HistoryCalendarSwipeTrackingView,
        context: Context
    ) {
        context.coordinator.update(
            isEnabled: isEnabled,
            canNavigateBackward: canNavigateBackward,
            canNavigateForward: canNavigateForward,
            onBegan: onBegan,
            onProgress: onProgress,
            onReleased: onReleased
        )
    }

    static func dismantleNSView(
        _ nsView: HistoryCalendarSwipeTrackingView,
        coordinator: Coordinator
    ) {
        coordinator.invalidate()
    }

    @MainActor
    final class Coordinator {
        private weak var trackingView: HistoryCalendarSwipeTrackingView?
        nonisolated(unsafe) private var eventMonitor: Any?
        private var isTracking = false
        private var generation: UInt = 0
        private var isEnabled = true
        private var canNavigateBackward = false
        private var canNavigateForward = false
        private var lastProgress = CGFloat.zero
        private var lastProgressTimestamp: TimeInterval?
        private var currentVelocity = CGFloat.zero
        private var onBegan: (@MainActor () -> Void)?
        private var onProgress: (@MainActor (CGFloat) -> Void)?
        private var onReleased: (@MainActor (HistoryCalendarSwipeDirection?) -> Void)?

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }

        func attach(to view: HistoryCalendarSwipeTrackingView) {
            trackingView = view
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func update(
            isEnabled: Bool,
            canNavigateBackward: Bool,
            canNavigateForward: Bool,
            onBegan: @escaping @MainActor () -> Void,
            onProgress: @escaping @MainActor (CGFloat) -> Void,
            onReleased: @escaping @MainActor (HistoryCalendarSwipeDirection?) -> Void
        ) {
            self.isEnabled = isEnabled
            self.canNavigateBackward = canNavigateBackward
            self.canNavigateForward = canNavigateForward
            self.onBegan = onBegan
            self.onProgress = onProgress
            self.onReleased = onReleased
        }

        func invalidate() {
            generation &+= 1
            isTracking = false
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            trackingView = nil
            onBegan = nil
            onProgress = nil
            onReleased = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isEnabled else { return event }
            guard let trackingView,
                event.window === trackingView.window
            else { return event }

            if isTracking {
                return nil
            }

            let location = trackingView.convert(event.locationInWindow, from: nil)
            guard trackingView.bounds.contains(location) else { return event }

            let shouldBegin = HistoryCalendarSwipePolicy.shouldBegin(
                swipeTrackingIsEnabled: NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                hasPreciseScrollingDeltas: event.hasPreciseScrollingDeltas,
                isBeginning: event.phase.contains(.began),
                horizontalDelta: event.scrollingDeltaX,
                verticalDelta: event.scrollingDeltaY
            )
            guard shouldBegin else { return event }

            let limits = HistoryCalendarSwipePolicy.limits(
                canNavigateBackward: canNavigateBackward,
                canNavigateForward: canNavigateForward
            )
            generation &+= 1
            let trackedGeneration = generation
            isTracking = true
            lastProgress = 0
            lastProgressTimestamp = ProcessInfo.processInfo.systemUptime
            currentVelocity = 0
            onBegan?()

            event.trackSwipeEvent(
                options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: limits.minimumProgress,
                max: limits.maximumProgress
            ) { [weak self] progress, phase, isComplete, stop in
                // AppKit invokes tracking callbacks on the main event loop that started tracking.
                MainActor.assumeIsolated {
                    let shouldStop =
                        self?.receive(
                            progress: progress,
                            phase: phase,
                            isComplete: isComplete,
                            generation: trackedGeneration
                        ) ?? false
                    if shouldStop {
                        stop.pointee = true
                    }
                }
            }
            return nil
        }

        private func receive(
            progress: CGFloat,
            phase: NSEvent.Phase,
            isComplete: Bool,
            generation: UInt
        ) -> Bool {
            guard generation == self.generation, isTracking else { return true }
            let normalizedProgress = HistoryCalendarSwipePolicy.normalizedProgress(progress)
            if !phase.contains(.ended),
                !phase.contains(.cancelled),
                !phase.contains(.mayBegin)
            {
                updateVelocity(for: normalizedProgress)
            }
            onProgress?(normalizedProgress)

            if phase.contains(.cancelled) || phase.contains(.mayBegin) {
                release(direction: nil)
                return true
            }
            if phase.contains(.ended) {
                release(
                    direction: HistoryCalendarSwipePolicy.releasedDirection(
                        for: normalizedProgress,
                        velocity: currentVelocity,
                        canNavigateBackward: canNavigateBackward,
                        canNavigateForward: canNavigateForward
                    )
                )
                return true
            }
            guard isComplete else { return false }
            release(
                direction: HistoryCalendarSwipePolicy.completedDirection(
                    for: normalizedProgress
                )
            )
            return false
        }

        private func updateVelocity(for progress: CGFloat) {
            let timestamp = ProcessInfo.processInfo.systemUptime
            defer {
                lastProgress = progress
                lastProgressTimestamp = timestamp
            }
            guard let lastProgressTimestamp else { return }
            let elapsed = max(0.008, timestamp - lastProgressTimestamp)
            currentVelocity = (progress - lastProgress) / elapsed
        }

        private func release(direction: HistoryCalendarSwipeDirection?) {
            isTracking = false
            onReleased?(direction)
        }
    }
}

final class HistoryCalendarSwipeTrackingView: NSView {
    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
