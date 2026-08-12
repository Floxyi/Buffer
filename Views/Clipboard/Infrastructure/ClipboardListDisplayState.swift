import Foundation

struct ClipboardListDisplayState {
    let displayRows: [ClipboardListStructure.DisplayRow]
    let layoutIndex: ClipboardListLayoutIndex
    let contentTrailingPadding: CGFloat
}

struct ClipboardListDisplayStateProjector {
    func project(
        items: [ClipboardItem],
        cache: ClipboardListStructure.DisplayCache,
        viewportHeight: CGFloat
    ) -> ClipboardListDisplayState {
        let displayCache: ClipboardListStructure.DisplayCache
        if cache.matches(items: items) {
            displayCache = cache
        } else {
            displayCache = ClipboardListStructure.makeDisplayCache(from: items)
        }

        let displayRows = displayCache.displayRows
        let contentHeight = displayCache.layoutIndex.contentHeight
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
            displayRows: displayRows,
            layoutIndex: displayCache.layoutIndex,
            contentTrailingPadding: contentTrailingPadding
        )
    }
}
