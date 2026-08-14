import Foundation

struct ClipboardListDisplayState {
    let cache: ClipboardListStructure.DisplayCache
    let displayRows: [ClipboardListStructure.DisplayRow]
    let layoutIndex: ClipboardListLayoutIndex
    let contentTrailingPadding: CGFloat
}

struct ClipboardListDisplayStateProjector {
    func project(
        items: [ClipboardItem],
        itemsSnapshotID: UUID,
        cache: ClipboardListStructure.DisplayCache,
        viewportHeight: CGFloat
    ) -> ClipboardListDisplayState {
        let resolvedCache: ClipboardListStructure.DisplayCache
        if cache.matches(sourceSnapshotID: itemsSnapshotID) {
            resolvedCache = cache
        } else {
            resolvedCache = ClipboardListStructure.makeDisplayCache(
                from: items,
                sourceSnapshotID: itemsSnapshotID
            )
        }

        let displayRows = resolvedCache.displayRows
        let contentHeight = resolvedCache.layoutIndex.contentHeight
        let hasVisibleScrollbar = viewportHeight > 1 && max(0, contentHeight - viewportHeight) > 1
        let contentTrailingPadding: CGFloat
        if hasVisibleScrollbar {
            contentTrailingPadding =
                ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2
                * ClipboardListStructure.LayoutMetrics.contentPadding
        } else {
            contentTrailingPadding = ClipboardListStructure.LayoutMetrics.contentPadding
        }

        return ClipboardListDisplayState(
            cache: resolvedCache,
            displayRows: displayRows,
            layoutIndex: resolvedCache.layoutIndex,
            contentTrailingPadding: contentTrailingPadding
        )
    }
}
