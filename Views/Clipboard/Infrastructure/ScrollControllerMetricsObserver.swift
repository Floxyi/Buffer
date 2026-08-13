import AppKit
import Foundation

@MainActor
final class ScrollControllerMetricsObserver {
    private weak var observedScrollView: NSScrollView?
    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var scheduledSyncTask: Task<Void, Never>?
    private var syncGeneration: UInt = 0

    func configure(
        scrollView: NSScrollView,
        onSyncRequested: @escaping @Sendable @MainActor (NSScrollView) -> Void
    ) {
        if observedScrollView === scrollView,
            observedDocumentView === scrollView.documentView
        {
            scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
            return
        }

        removeObservers()
        observedScrollView = scrollView
        observedDocumentView = scrollView.documentView
        startObserving(scrollView: scrollView, onSyncRequested: onSyncRequested)
        scheduleSync(for: scrollView, onSyncRequested: onSyncRequested)
    }

    func scheduleSync(
        for scrollView: NSScrollView,
        onSyncRequested: @escaping @Sendable @MainActor (NSScrollView) -> Void
    ) {
        guard scheduledSyncTask == nil else { return }

        syncGeneration &+= 1
        let scheduledGeneration = syncGeneration
        scheduledSyncTask = Task { @MainActor [weak self, weak scrollView] in
            guard let self else { return }
            await Task.yield()

            guard scheduledGeneration == self.syncGeneration else { return }
            self.scheduledSyncTask = nil

            guard !Task.isCancelled,
                let scrollView,
                self.observedScrollView === scrollView,
                self.observedDocumentView === scrollView.documentView
            else {
                return
            }
            onSyncRequested(scrollView)
        }
    }

    func removeObservers() {
        syncGeneration &+= 1
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observedScrollView = nil
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

            observers.append(
                center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
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
