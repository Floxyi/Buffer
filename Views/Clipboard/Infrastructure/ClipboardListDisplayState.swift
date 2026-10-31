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
        guard cache.matches(sourceSnapshotID: itemsSnapshotID) else {
            assertionFailure("A list publication must include its matching display cache")
            return makeDisplayState(cache: cache, viewportHeight: viewportHeight)
        }

        return makeDisplayState(cache: cache, viewportHeight: viewportHeight)
    }

    private func makeDisplayState(
        cache: ClipboardListStructure.DisplayCache,
        viewportHeight: CGFloat
    ) -> ClipboardListDisplayState {
        let displayRows = cache.displayRows
        let contentHeight = cache.layoutIndex.contentHeight
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
            cache: cache,
            displayRows: displayRows,
            layoutIndex: cache.layoutIndex,
            contentTrailingPadding: contentTrailingPadding
        )
    }
}
