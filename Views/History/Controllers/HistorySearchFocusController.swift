import AppKit
import Foundation

@MainActor
final class HistorySearchFocusController: ObservableObject {
    @Published var isSearchFocused = false

    private var shouldRefocusSearchOnActivate = false

    func handleAppear(isAppActive: Bool) {
        guard isAppActive else { return }
        focusSearchField()
    }

    func handleWindowOpen(shouldFocusSearch: Bool) {
        guard shouldFocusSearch else { return }
        shouldRefocusSearchOnActivate = true
        focusSearchField()
    }

    func handleDidBecomeActive() {
        guard shouldRefocusSearchOnActivate else { return }

        focusSearchField()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            self.shouldRefocusSearchOnActivate = false
        }
    }

    private func focusSearchField() {
        isSearchFocused = false

        Task { @MainActor in
            self.isSearchFocused = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            self.isSearchFocused = true
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.isSearchFocused = true
        }
    }
}
