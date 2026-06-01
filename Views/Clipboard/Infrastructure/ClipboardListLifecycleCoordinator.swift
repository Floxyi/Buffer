import Foundation

@MainActor
struct ClipboardListLifecycleCoordinator {
    func handleAppear(
        items: [ClipboardItem],
        settings: SettingsManager,
        prewarmVisibleAssets: ([ClipboardItem], SettingsManager) -> Void,
        currentScrollOffsetSnapshot: @escaping () -> CGFloat,
        syncScrollMetrics: @escaping () -> Void,
        onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void),
        onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void),
        restoreScrollOffset: @escaping (CGFloat) -> Void,
        applyOpenScrollRequestIfPossible: @escaping () -> Void
    ) {
        prewarmVisibleAssets(items, settings)
        onScrollOffsetProviderChanged {
            syncScrollMetrics()
            return currentScrollOffsetSnapshot()
        }
        onScrollOffsetRestorerChanged(restoreScrollOffset)
        applyOpenScrollRequestIfPossible()
    }

    func handleDisappear(
        cancelVisibleAssetPrewarm: () -> Void,
        cancelScrolling: () -> Void,
        onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void),
        onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)
    ) {
        cancelVisibleAssetPrewarm()
        cancelScrolling()
        onScrollOffsetProviderChanged(nil)
        onScrollOffsetRestorerChanged(nil)
    }
}
