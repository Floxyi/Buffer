import Foundation

@MainActor
final class ClipboardListAssetPrewarmer {
    private var visibleAssetTask: Task<Void, Never>?
    private var keyboardNavigationAssetTask: Task<Void, Never>?

    func prewarmVisibleAssets(in items: [ClipboardItem], settings: SettingsManager) {
        visibleAssetTask?.cancel()

        let visibleItems = Self.visiblePrewarmItems(from: items)
        visibleAssetTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmSourceIcons(
                for: visibleItems,
                settings: settings,
                limit: 72
            )
        }
    }

    func prewarmAssetsForKeyboardNavigation(
        request: HistoryKeyboardNavigationRequest,
        items: [ClipboardItem],
        settings: SettingsManager
    ) {
        keyboardNavigationAssetTask?.cancel()

        let nearbyItems = Self.keyboardNavigationPrewarmItems(
            for: request,
            in: items
        )
        keyboardNavigationAssetTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmSourceIcons(
                for: nearbyItems,
                settings: settings,
                limit: 20
            )
        }
    }

    func cancelAll() {
        visibleAssetTask?.cancel()
        visibleAssetTask = nil

        keyboardNavigationAssetTask?.cancel()
        keyboardNavigationAssetTask = nil
    }

    nonisolated static func visiblePrewarmItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        Array(items.prefix(160))
    }

    nonisolated static func keyboardNavigationPrewarmItems(
        for request: HistoryKeyboardNavigationRequest,
        in items: [ClipboardItem]
    ) -> [ClipboardItem] {
        let startIndex = max(0, request.targetIndex - 8)
        let endIndex = min(items.count, request.targetIndex + 9)
        return Array(items[startIndex..<endIndex])
    }
}
