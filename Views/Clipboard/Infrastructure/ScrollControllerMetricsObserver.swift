import AppKit
import Foundation

@MainActor
final class ScrollControllerMetricsObserver {
    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var isSyncScheduled = false

    func configure(
        scrollView: NSScrollView,
        onSyncRequested: @escaping @Sendable @MainActor (NSScrollView) -> Void
    ) {
        let documentViewChanged = observedDocumentView !== scrollView.documentView

        if observedDocumentView != nil, !documentViewChanged {
            scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
            return
        }

        removeObservers()
        observedDocumentView = scrollView.documentView
        startObserving(scrollView: scrollView, onSyncRequested: onSyncRequested)
        scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
    }

    func scheduleSync(
        for scrollView: NSScrollView,
        onSyncRequested: @escaping @Sendable @MainActor (NSScrollView) -> Void
    ) {
        guard !isSyncScheduled else { return }

        isSyncScheduled = true

        Task { @MainActor [weak self, weak scrollView] in
            guard let self else { return }
            await Task.yield()

            self.isSyncScheduled = false

            guard let scrollView else { return }
            onSyncRequested(scrollView)
        }
    }

    func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedDocumentView = nil
    }

    private func startObserving(
        scrollView: NSScrollView,
        onSyncRequested: @escaping @Sendable @MainActor (NSScrollView) -> Void
    ) {
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
                    self.scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
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
                    self.scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
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
                        self.scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
                    }
                }
            )
        }
    }
}
