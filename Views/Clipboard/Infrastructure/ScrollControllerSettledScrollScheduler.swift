import Foundation

@MainActor
final class ScrollControllerSettledScrollScheduler {
    private var currentTask: Task<Void, Never>?
    private var generation: UInt = 0

    func schedule(retryCount: Int, action: @escaping @MainActor () -> Void) {
        cancel()
        generation &+= 1
        let currentGeneration = generation

        currentTask = Task { @MainActor in
            for _ in 0...max(0, retryCount) {
                guard !Task.isCancelled else { return }
                await Task.yield()
                guard currentGeneration == generation else { return }
                action()
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        generation &+= 1
    }
}
