import Foundation

@MainActor
final class ScrollControllerSettledScrollScheduler {
    private var currentTask: Task<Void, Never>?

    func schedule(retryCount: Int, action: @escaping @MainActor () -> Void) {
        cancel()

        currentTask = Task { @MainActor in
            for _ in 0...max(0, retryCount) {
                guard !Task.isCancelled else { return }
                await Task.yield()
                action()
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}
