import Foundation

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
