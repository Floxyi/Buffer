import Foundation

final class ClipboardStoreRetentionScheduler: @unchecked Sendable {
    private let intervalNanoseconds: UInt64
    private var task: Task<Void, Never>?

    init(intervalNanoseconds: UInt64 = 60_000_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    func start(action: @escaping @Sendable @MainActor () async -> Void) {
        guard task == nil else { return }
        let intervalNanoseconds = intervalNanoseconds

        task = Task {
            while !Task.isCancelled {
                await action()
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
