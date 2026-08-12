import Foundation

@MainActor
final class ScrollActivityTracker {
    private(set) var isScrolling = false

    private var idleTimer: Timer?
    private let idleDelay: TimeInterval = 0.12

    deinit {
        MainActor.assumeIsolated {
            idleTimer?.invalidate()
        }
    }

    func markScrolling() {
        if !isScrolling {
            isScrolling = true
        }

        if let idleTimer {
            idleTimer.fireDate = Date(timeIntervalSinceNow: idleDelay)
            return
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: idleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isScrolling = false
                self?.idleTimer = nil
            }
        }
    }
}
