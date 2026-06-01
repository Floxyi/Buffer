import Foundation

struct ClipboardListDisplayState {
    let displayRows: [ClipboardListStructure.DisplayRow]
    let contentTrailingPadding: CGFloat
}

struct ClipboardListDisplayStateProjector {
    func project(
        items: [ClipboardItem],
        cache: ClipboardListStructure.DisplayCache,
        viewportHeight: CGFloat
    ) -> ClipboardListDisplayState {
        let displayRows: [ClipboardListStructure.DisplayRow]
        if cache.matches(items: items) {
            displayRows = cache.displayRows
        } else {
            displayRows = ClipboardListStructure.displayRows(from: items)
        }

        let contentHeight = ClipboardListStructure.estimatedContentHeight(for: displayRows)
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
            contentTrailingPadding: contentTrailingPadding
        )
    }
}
