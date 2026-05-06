import AppKit
import SwiftUI

@MainActor
final class ScrollController: ObservableObject {
    @Published private(set) var viewportHeight: CGFloat = 0
    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var scrollOffset: CGFloat = 0

    weak var scrollView: NSScrollView?

    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var isMetricsSyncScheduled = false

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
        }
    }

    func configure(scrollView: NSScrollView) {
        let documentViewChanged = observedDocumentView !== scrollView.documentView

        if self.scrollView === scrollView, !documentViewChanged {
            scheduleMetricsSync(from: scrollView)
            return
        }

        removeObservers()

        self.scrollView = scrollView
        observedDocumentView = scrollView.documentView

        startObserving(scrollView: scrollView)
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

    func scrollToTop(retryCount: Int = 4) {
        scheduleScrollToTop(remainingPasses: retryCount)
    }

    func scrollToTopImmediately() {
        scrollToTopNow()
    }

    func syncMetrics() {
        guard let scrollView else { return }
        scheduleMetricsSync(from: scrollView)
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
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}
