import CoreGraphics

@MainActor
final class HistoryListScrollRestorationCoordinator {
    private var lastListScrollOffset = CGFloat.zero
    private var pendingListScrollOffsetRestore: CGFloat?
    private var listScrollOffsetProvider: (() -> CGFloat)?
    private var listScrollOffsetRestorer: ((CGFloat) -> Void)?

    func captureCurrentOffset() {
        lastListScrollOffset = max(0, listScrollOffsetProvider?() ?? lastListScrollOffset)
    }

    func restoreIfNeeded(for openBehavior: HistoryWindowOpenBehavior) {
        guard openBehavior == .keepLastSelection else {
            pendingListScrollOffsetRestore = nil
            return
        }

        let offset = max(0, lastListScrollOffset)
        guard offset > 0.5 else {
            pendingListScrollOffsetRestore = nil
            return
        }

        if let listScrollOffsetRestorer {
            pendingListScrollOffsetRestore = nil
            listScrollOffsetRestorer(offset)
        } else {
            pendingListScrollOffsetRestore = offset
        }
    }

    func setOffsetProvider(_ provider: (() -> CGFloat)?) {
        listScrollOffsetProvider = provider
    }

    func setOffsetRestorer(_ restorer: ((CGFloat) -> Void)?) {
        listScrollOffsetRestorer = restorer

        guard let restorer, let pendingListScrollOffsetRestore else {
            return
        }

        self.pendingListScrollOffsetRestore = nil
        restorer(pendingListScrollOffsetRestore)
    }
}
