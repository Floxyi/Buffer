import Foundation
import SwiftUI

struct ClipboardListRenderingWindow: Equatable {
    let range: Range<Int>
    let leadingSpacerHeight: CGFloat
    let trailingSpacerHeight: CGFloat

    static let empty = ClipboardListRenderingWindow(
        range: 0..<0,
        leadingSpacerHeight: 0,
        trailingSpacerHeight: 0
    )

    static func make(
        range: Range<Int>,
        rowEntries: [ClipboardListLayoutIndex.RowEntry],
        contentHeight: CGFloat
    ) -> ClipboardListRenderingWindow {
        guard let firstIndex = range.first,
            let lastIndex = range.last,
            rowEntries.indices.contains(firstIndex),
            rowEntries.indices.contains(lastIndex)
        else { return .empty }

        let metrics = ClipboardListStructure.LayoutMetrics.self
        let firstFrame = rowEntries[firstIndex].frame
        let lastFrame = rowEntries[lastIndex].frame
        let leadingHeight = max(0, firstFrame.minY - metrics.contentPadding)
        let trailingHeight = max(
            0,
            contentHeight - metrics.contentPadding - lastFrame.maxY
        )
        return ClipboardListRenderingWindow(
            range: range,
            leadingSpacerHeight: leadingHeight,
            trailingSpacerHeight: trailingHeight
        )
    }
}

/// Keeps a bounded, deterministic row window around the viewport. Unlike
/// `LazyVStack`, its outer spacers preserve the exact document height while a
/// mutation is reconciled, so AppKit never has to clamp a valid deep offset to
/// a transient content estimate.
@MainActor
final class ClipboardListRenderingWindowCoordinator: ObservableObject {
    private enum Metrics {
        static let overscan = CGFloat(720)
        static let retainedOverscan = CGFloat(240)
        static let minimumViewportHeight = CGFloat(420)
    }

    @Published private(set) var renderingWindow = ClipboardListRenderingWindow.empty

    private var sourceSnapshotID: UUID?
    private var sourceQuery: ClipboardQuery?
    private var latestRequestedSnapshotID: UUID?

    func resolvedWindow(
        snapshotID: UUID,
        query: ClipboardQuery,
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        pinnedItemCount: Int
    ) -> ClipboardListRenderingWindow {
        // `resolvedWindow` is evaluated as part of the new SwiftUI body before
        // the preceding snapshot's metrics callback is necessarily detached.
        // Remember that publication immediately so a late callback cannot put
        // the old rendering window back for one frame.
        latestRequestedSnapshotID = snapshotID
        if sourceSnapshotID == snapshotID, !renderingWindow.range.isEmpty {
            return renderingWindow
        }

        return nextWindow(
            query: query,
            layoutIndex: layoutIndex,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            pinnedItemCount: pinnedItemCount
        )
    }

    func update(
        snapshotID: UUID,
        query: ClipboardQuery,
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        pinnedItemCount: Int
    ) {
        guard latestRequestedSnapshotID == nil || latestRequestedSnapshotID == snapshotID else {
            return
        }
        let nextWindow = nextWindow(
            query: query,
            layoutIndex: layoutIndex,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            pinnedItemCount: pinnedItemCount
        )
        sourceSnapshotID = snapshotID
        sourceQuery = query
        guard nextWindow != renderingWindow else { return }
        renderingWindow = nextWindow
    }

    private func nextWindow(
        query: ClipboardQuery,
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        pinnedItemCount: Int
    ) -> ClipboardListRenderingWindow {
        if sourceQuery == query,
            let retainedWindow = Self.retainedWindow(
                renderingWindow,
                layoutIndex: layoutIndex,
                scrollOffset: scrollOffset,
                viewportHeight: viewportHeight,
                pinnedItemCount: pinnedItemCount
            )
        {
            return retainedWindow
        }

        return Self.makeWindow(
            layoutIndex: layoutIndex,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            pinnedItemCount: pinnedItemCount
        )
    }

    private static func retainedWindow(
        _ currentWindow: ClipboardListRenderingWindow,
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        pinnedItemCount: Int
    ) -> ClipboardListRenderingWindow? {
        guard !currentWindow.range.isEmpty, !layoutIndex.rowEntries.isEmpty else { return nil }

        let lowerBound = min(currentWindow.range.lowerBound, layoutIndex.rowEntries.count - 1)
        let upperBound = min(
            max(lowerBound + 1, currentWindow.range.upperBound),
            layoutIndex.rowEntries.count
        )
        let range = lowerBound..<upperBound
        guard let firstEntry = layoutIndex.rowEntries[safe: range.lowerBound],
            let lastEntry = layoutIndex.rowEntries[safe: range.upperBound - 1]
        else { return nil }

        let visibleMinimumY = max(0, scrollOffset)
        let visibleMaximumY = min(
            layoutIndex.contentHeight,
            scrollOffset + max(viewportHeight, Metrics.minimumViewportHeight)
        )
        let retainsLeadingCoverage =
            range.lowerBound == 0
            || firstEntry.frame.minY <= visibleMinimumY - Metrics.retainedOverscan
        let retainsTrailingCoverage =
            range.upperBound == layoutIndex.rowEntries.count
            || lastEntry.frame.maxY >= visibleMaximumY + Metrics.retainedOverscan
        guard retainsLeadingCoverage, retainsTrailingCoverage else { return nil }

        return windowIncludingPinnedBlockIfNeeded(
            ClipboardListRenderingWindow.make(
                range: range,
                rowEntries: layoutIndex.rowEntries,
                contentHeight: layoutIndex.contentHeight
            ),
            layoutIndex: layoutIndex,
            pinnedItemCount: pinnedItemCount
        )
    }

    private static func makeWindow(
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        pinnedItemCount: Int
    ) -> ClipboardListRenderingWindow {
        let proposedWindow = layoutIndex.renderingWindow(
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: Metrics.overscan
        )
        return windowIncludingPinnedBlockIfNeeded(
            proposedWindow,
            layoutIndex: layoutIndex,
            pinnedItemCount: pinnedItemCount
        )
    }

    private static func windowIncludingPinnedBlockIfNeeded(
        _ proposedWindow: ClipboardListRenderingWindow,
        layoutIndex: ClipboardListLayoutIndex,
        pinnedItemCount: Int
    ) -> ClipboardListRenderingWindow {
        guard !proposedWindow.range.isEmpty, pinnedItemCount > 0 else { return proposedWindow }

        // The draggable pin block has one shared interaction container. When
        // any part of it enters the rendering corridor, materialize that small
        // block as a unit so drag previews and insertion targets stay native.
        let pinnedBlockEnd = min(layoutIndex.rowEntries.count, pinnedItemCount + 1)
        guard proposedWindow.range.lowerBound < pinnedBlockEnd else {
            return proposedWindow
        }
        return ClipboardListRenderingWindow.make(
            range: 0..<max(proposedWindow.range.upperBound, pinnedBlockEnd),
            rowEntries: layoutIndex.rowEntries,
            contentHeight: layoutIndex.contentHeight
        )
    }
}

struct ClipboardListDisplayState {
    let cache: ClipboardListStructure.DisplayCache
    let displayRows: [ClipboardListStructure.DisplayRow]
    let layoutIndex: ClipboardListLayoutIndex
    let contentTrailingPadding: CGFloat
}

struct ClipboardListDisplayStateProjector {
    func project(
        snapshotID: UUID,
        cache: ClipboardListStructure.DisplayCache,
        viewportHeight: CGFloat
    ) -> ClipboardListDisplayState {
        guard cache.matches(sourceSnapshotID: snapshotID) else {
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
