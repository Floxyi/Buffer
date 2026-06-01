import Combine
import Foundation

@MainActor
final class ClipboardStoreSettingsCoordinator {
    private var cancellables: Set<AnyCancellable> = []

    func bind(
        settingsManager: SettingsManager,
        onHistoryLimitChange: @escaping @MainActor (Int) -> Void,
        onHistoryRetentionPeriodChange: @escaping @MainActor () -> Void
    ) {
        settingsManager.$historyLimit
            .dropFirst()
            .removeDuplicates()
            .sink { limit in
                onHistoryLimitChange(limit)
            }
            .store(in: &cancellables)

        settingsManager.$historyRetentionPeriod
            .dropFirst()
            .removeDuplicates()
            .sink { _ in
                onHistoryRetentionPeriodChange()
            }
            .store(in: &cancellables)
    }
}
