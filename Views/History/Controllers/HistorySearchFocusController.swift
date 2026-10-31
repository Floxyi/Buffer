import AppKit
import Foundation

@MainActor
final class HistorySearchFocusController: ObservableObject {
    @Published var isSearchFocused = false

    private var shouldRefocusSearchOnActivate = false
    private var focusTask: Task<Void, Never>?
    private var activationResetTask: Task<Void, Never>?

    deinit {
        focusTask?.cancel()
        activationResetTask?.cancel()
    }

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

        activationResetTask?.cancel()
        activationResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            self?.shouldRefocusSearchOnActivate = false
            self?.activationResetTask = nil
        }
    }

    private func focusSearchField() {
        guard !isSearchFocused else { return }

        focusTask?.cancel()
        focusTask = Task { @MainActor [weak self] in
            // AppKit normally assigns the initial first responder while the
            // window is completing its first layout pass. Give that automatic
            // focus a chance to settle before issuing an explicit request; two
            // competing requests make TextInputUI repeatedly connect and tear
            // down its remote cursor service during launch.
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let self else { return }
            defer { focusTask = nil }
            guard !isSearchFocused else { return }
            isSearchFocused = true
        }
    }
}
