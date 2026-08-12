import Foundation

@MainActor
final class ClipboardListAssetPrewarmer {
    enum ScrollDirection: Hashable {
        case upward
        case downward
    }

    struct VisiblePrewarmSignature: Equatable {
        let anchorBucket: Int
        let direction: ScrollDirection
        let itemCount: Int
        let viewportItemCount: Int
    }

    struct VisiblePrewarmPlan {
        let items: [ClipboardItem]
        let signature: VisiblePrewarmSignature
    }

    private var visibleAssetTask: Task<Void, Never>?
    private var keyboardNavigationAssetTask: Task<Void, Never>?
    private var visiblePrewarmSignature: VisiblePrewarmSignature?
    private var keyboardPrewarmSignature: Int?
    private var lastScrollOffset: CGFloat?
    private var lastKeyboardTargetIndex: Int?
    private var scrollDirection = ScrollDirection.downward
    private let rowLeadingVisualSize = CGFloat(28)

    func prewarmVisibleAssets(
        in items: [ClipboardItem],
        store: ClipboardStore,
        settings: SettingsManager
    ) {
        visibleAssetTask?.cancel()
        visiblePrewarmSignature = nil
        lastScrollOffset = nil

        let visibleItems = Self.visiblePrewarmItems(from: items)
        visibleAssetTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmImageAssets(
                for: visibleItems,
                store: store,
                leadingVisualSize: rowLeadingVisualSize,
                limit: 32
            )
        }
    }

    func prewarmVisibleAssets(
        in items: [ClipboardItem],
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        store: ClipboardStore,
        settings: SettingsManager
    ) {
        updateScrollDirection(for: scrollOffset)
        let plan = Self.prioritizedVisiblePrewarmPlan(
            from: items,
            layoutIndex: layoutIndex,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            direction: scrollDirection
        )

        guard plan.signature != visiblePrewarmSignature else {
            return
        }

        visibleAssetTask?.cancel()
        visiblePrewarmSignature = plan.signature

        visibleAssetTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmImageAssets(
                for: plan.items,
                store: store,
                leadingVisualSize: rowLeadingVisualSize,
                limit: 24
            )
        }
    }

    func prewarmAssetsForKeyboardNavigation(
        request: HistoryKeyboardNavigationRequest,
        items: [ClipboardItem],
        store: ClipboardStore,
        settings: SettingsManager
    ) {
        let direction: ScrollDirection =
            if let lastKeyboardTargetIndex, request.targetIndex < lastKeyboardTargetIndex {
                .upward
            } else {
                .downward
            }
        self.lastKeyboardTargetIndex = request.targetIndex

        let bucketSize = 12
        let directionalBucket = request.targetIndex / bucketSize * 2 + (direction == .downward ? 1 : 0)
        guard directionalBucket != keyboardPrewarmSignature else {
            return
        }

        keyboardNavigationAssetTask?.cancel()
        keyboardPrewarmSignature = directionalBucket

        let nearbyItems = Self.prioritizedKeyboardNavigationPrewarmItems(
            for: request,
            in: items,
            direction: direction
        )
        keyboardNavigationAssetTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmImageAssets(
                for: nearbyItems,
                store: store,
                leadingVisualSize: rowLeadingVisualSize,
                limit: 8
            )
        }
    }

    func cancelAll() {
        visibleAssetTask?.cancel()
        visibleAssetTask = nil
        visiblePrewarmSignature = nil
        lastScrollOffset = nil

        keyboardNavigationAssetTask?.cancel()
        keyboardNavigationAssetTask = nil
        keyboardPrewarmSignature = nil
        lastKeyboardTargetIndex = nil
    }

    nonisolated static func visiblePrewarmItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        Array(items.prefix(160))
    }

    nonisolated static func visiblePrewarmItems(
        from items: [ClipboardItem],
        displayRows: [ClipboardListStructure.DisplayRow],
        scrollOffset: CGFloat,
        viewportHeight: CGFloat
    ) -> [ClipboardItem] {
        guard viewportHeight > 0, !displayRows.isEmpty else {
            return visiblePrewarmItems(from: items)
        }

        let overscan = max(
            viewportHeight * 1.35,
            ClipboardListStructure.LayoutMetrics.itemRowHeight * 14
        )
        let visibleIDs = ClipboardListStructure.visibleItemIDs(
            in: displayRows,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: overscan
        )
        guard !visibleIDs.isEmpty else {
            return visiblePrewarmItems(from: items)
        }

        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return visibleIDs.compactMap { itemByID[$0] }
    }

    nonisolated static func prioritizedVisiblePrewarmPlan(
        from items: [ClipboardItem],
        layoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        direction: ScrollDirection
    ) -> VisiblePrewarmPlan {
        let viewportItemCount = max(
            1,
            Int(ceil(viewportHeight / ClipboardListStructure.LayoutMetrics.itemRowHeight))
        )
        let fallbackSignature = VisiblePrewarmSignature(
            anchorBucket: 0,
            direction: direction,
            itemCount: items.count,
            viewportItemCount: viewportItemCount
        )
        let visibleEntries = layoutIndex.visibleItemEntries(
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight
        )
        guard let firstVisibleEntry = visibleEntries.indices.first,
              let lastVisibleEntry = visibleEntries.indices.last
        else {
            return VisiblePrewarmPlan(
                items: Array(items.prefix(32)),
                signature: fallbackSignature
            )
        }

        // This is a latency optimization only. It is deliberately finite and small;
        // row correctness never depends on prefetch winning a race with scrolling.
        let behindCount = viewportItemCount
        let aheadCount = viewportItemCount * 3
        let lowerBound = max(
            0,
            firstVisibleEntry - (direction == .downward ? behindCount : aheadCount)
        )
        let upperBound = min(
            layoutIndex.entries.count,
            lastVisibleEntry + 1 + (direction == .downward ? aheadCount : behindCount)
        )
        let visible = Array(firstVisibleEntry...lastVisibleEntry)
        let lower = firstVisibleEntry > lowerBound ? Array(lowerBound..<firstVisibleEntry) : []
        let upper = upperBound > lastVisibleEntry + 1
            ? Array((lastVisibleEntry + 1)..<upperBound)
            : []
        let indices: [Int]
        switch direction {
        case .downward:
            indices = visible + upper + Array(lower.reversed())
        case .upward:
            indices = Array(visible.reversed()) + Array(lower.reversed()) + upper
        }

        return VisiblePrewarmPlan(
            items: indices.compactMap { entryIndex in
                let itemIndex = layoutIndex.entries[entryIndex].itemIndex
                return items[safe: itemIndex]
            },
            signature: VisiblePrewarmSignature(
                anchorBucket: firstVisibleEntry,
                direction: direction,
                itemCount: items.count,
                viewportItemCount: viewportItemCount
            )
        )
    }

    nonisolated static func prioritizedVisiblePrewarmPlan(
        from items: [ClipboardItem],
        displayRows: [ClipboardListStructure.DisplayRow],
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        direction: ScrollDirection
    ) -> VisiblePrewarmPlan {
        let viewportItemCount = max(
            1,
            Int(ceil(viewportHeight / ClipboardListStructure.LayoutMetrics.itemRowHeight))
        )
        let fallbackSignature = VisiblePrewarmSignature(
            anchorBucket: 0,
            direction: direction,
            itemCount: items.count,
            viewportItemCount: viewportItemCount
        )

        guard viewportHeight > 0, !items.isEmpty, !displayRows.isEmpty else {
            return VisiblePrewarmPlan(
                items: visiblePrewarmItems(from: items),
                signature: fallbackSignature
            )
        }

        let visibleIDs = ClipboardListStructure.visibleItemIDs(
            in: displayRows,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: 0
        )
        let itemIndexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        let visibleIndices = visibleIDs.compactMap { itemIndexByID[$0] }
        guard let firstVisibleIndex = visibleIndices.min(),
            let lastVisibleIndex = visibleIndices.max()
        else {
            return VisiblePrewarmPlan(
                items: visiblePrewarmItems(from: items),
                signature: fallbackSignature
            )
        }

        let behindCount = viewportItemCount * 2
        let aheadCount = viewportItemCount * 10
        let lowerBound = max(0, firstVisibleIndex - (direction == .downward ? behindCount : aheadCount))
        let upperBound = min(items.count, lastVisibleIndex + 1 + (direction == .downward ? aheadCount : behindCount))

        let visibleRange = Array(firstVisibleIndex...lastVisibleIndex)
        let lowerRange =
            firstVisibleIndex > lowerBound
            ? Array(lowerBound..<firstVisibleIndex)
            : []
        let upperRange =
            upperBound > lastVisibleIndex + 1
            ? Array((lastVisibleIndex + 1)..<upperBound)
            : []

        let prioritizedIndices: [Int]
        switch direction {
        case .downward:
            prioritizedIndices = visibleRange + upperRange + Array(lowerRange.reversed())
        case .upward:
            prioritizedIndices = Array(visibleRange.reversed()) + Array(lowerRange.reversed()) + upperRange
        }

        let bucketSize = max(8, viewportItemCount * 3)
        let anchorIndex = direction == .downward ? firstVisibleIndex : lastVisibleIndex
        return VisiblePrewarmPlan(
            items: prioritizedIndices.map { items[$0] },
            signature: VisiblePrewarmSignature(
                anchorBucket: anchorIndex / bucketSize,
                direction: direction,
                itemCount: items.count,
                viewportItemCount: viewportItemCount
            )
        )
    }

    nonisolated static func keyboardNavigationPrewarmItems(
        for request: HistoryKeyboardNavigationRequest,
        in items: [ClipboardItem]
    ) -> [ClipboardItem] {
        let startIndex = max(0, request.targetIndex - 8)
        let endIndex = min(items.count, request.targetIndex + 9)
        return Array(items[startIndex..<endIndex])
    }

    nonisolated static func prioritizedKeyboardNavigationPrewarmItems(
        for request: HistoryKeyboardNavigationRequest,
        in items: [ClipboardItem],
        direction: ScrollDirection
    ) -> [ClipboardItem] {
        guard items.indices.contains(request.targetIndex) else {
            return []
        }

        let behindCount = 12
        let aheadCount = 120
        let lowerBound = max(
            0,
            request.targetIndex - (direction == .downward ? behindCount : aheadCount)
        )
        let upperBound = min(
            items.count,
            request.targetIndex + 1 + (direction == .downward ? aheadCount : behindCount)
        )

        let lowerIndices = Array(lowerBound..<request.targetIndex)
        let upperIndices =
            request.targetIndex + 1 < upperBound
            ? Array((request.targetIndex + 1)..<upperBound)
            : []
        let prioritizedIndices: [Int]

        switch direction {
        case .downward:
            prioritizedIndices = [request.targetIndex] + upperIndices + Array(lowerIndices.reversed())
        case .upward:
            prioritizedIndices = [request.targetIndex] + Array(lowerIndices.reversed()) + upperIndices
        }

        return prioritizedIndices.map { items[$0] }
    }

    private func updateScrollDirection(for scrollOffset: CGFloat) {
        defer { lastScrollOffset = scrollOffset }
        guard let lastScrollOffset else {
            return
        }

        if scrollOffset > lastScrollOffset + 0.5 {
            scrollDirection = .downward
        } else if scrollOffset < lastScrollOffset - 0.5 {
            scrollDirection = .upward
        }
    }
}
