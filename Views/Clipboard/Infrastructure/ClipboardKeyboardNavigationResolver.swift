import Foundation

struct ClipboardKeyboardNavigationMetrics: Equatable {
    let currentOffset: CGFloat
    let targetOffset: CGFloat
}

struct ClipboardKeyboardNavigationResolver {
    private static let comfortPadding = ClipboardListStructure.LayoutMetrics.itemRowHeight
    private static let topSnapThreshold =
        ClipboardListStructure.LayoutMetrics.contentPadding + ClipboardListStructure.LayoutMetrics.sectionHeaderHeight
        + ClipboardListStructure.LayoutMetrics.rowSpacing + ClipboardListStructure.LayoutMetrics.itemRowHeight

    func resolveMetrics(
        for itemID: UUID,
        layoutIndex: ClipboardListLayoutIndex,
        scrollMetrics: SmoothWheelScroller.Metrics
    ) -> ClipboardKeyboardNavigationMetrics? {
        guard let estimatedFrame = layoutIndex.frame(for: itemID) else {
            return nil
        }

        let viewportHeight = max(1, scrollMetrics.viewportHeight)
        let currentOffset = scrollMetrics.scrollOffset
        let maxOffset = max(0, scrollMetrics.contentHeight - viewportHeight)
        let visibleMinY = currentOffset + Self.comfortPadding
        let visibleMaxY = currentOffset + viewportHeight - Self.comfortPadding

        let rawTargetOffset: CGFloat?
        if estimatedFrame.minY < visibleMinY {
            rawTargetOffset = estimatedFrame.minY - Self.comfortPadding
        } else if estimatedFrame.maxY > visibleMaxY {
            rawTargetOffset = estimatedFrame.maxY - viewportHeight + Self.comfortPadding
        } else {
            rawTargetOffset = nil
        }

        guard let rawTargetOffset else {
            return nil
        }

        return ClipboardKeyboardNavigationMetrics(
            currentOffset: currentOffset,
            targetOffset: Self.resolvedTargetOffset(
                rawTargetOffset: rawTargetOffset,
                maxOffset: maxOffset
            )
        )
    }

    /// Compatibility entry point for non-interactive callers and older focused tests.
    /// Production navigation passes the already-built layout index.
    func resolveMetrics(
        for itemID: UUID,
        displayRows: [ClipboardListStructure.DisplayRow],
        scrollMetrics: SmoothWheelScroller.Metrics
    ) -> ClipboardKeyboardNavigationMetrics? {
        let itemIDs = displayRows.compactMap { row -> UUID? in
            guard case .item(let item) = row.kind else { return nil }
            return item.id
        }
        let itemIndexByID = Dictionary(
            uniqueKeysWithValues: itemIDs.enumerated().map { ($1, $0) }
        )
        return resolveMetrics(
            for: itemID,
            layoutIndex: ClipboardListLayoutIndex(
                rows: displayRows,
                itemIndexByID: itemIndexByID
            ),
            scrollMetrics: scrollMetrics
        )
    }

    static func resolvedTargetOffset(rawTargetOffset: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let clampedTargetOffset = rawTargetOffset.clamped(to: 0...maxOffset)
        if clampedTargetOffset <= topSnapThreshold {
            return 0
        }

        return clampedTargetOffset
    }
}
