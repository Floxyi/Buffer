import Foundation

struct ClipboardKeyboardNavigationMetrics: Equatable {
    let currentOffset: CGFloat
    let targetOffset: CGFloat
}

struct ClipboardKeyboardNavigationResolver {
    private static let comfortPadding = ClipboardListStructure.LayoutMetrics.itemRowHeight
    private static let topSnapThreshold =
        ClipboardListStructure.LayoutMetrics.contentPadding +
        ClipboardListStructure.LayoutMetrics.sectionHeaderHeight +
        ClipboardListStructure.LayoutMetrics.rowSpacing +
        ClipboardListStructure.LayoutMetrics.itemRowHeight

    func resolveMetrics(
        for itemID: UUID,
        displayRows: [ClipboardListStructure.DisplayRow],
        scrollMetrics: SmoothWheelScroller.Metrics
    ) -> ClipboardKeyboardNavigationMetrics? {
        guard let estimatedFrame = ClipboardListStructure.estimatedFrame(
            forItemID: itemID,
            in: displayRows
        ) else {
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

    static func resolvedTargetOffset(rawTargetOffset: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let clampedTargetOffset = rawTargetOffset.clamped(to: 0...maxOffset)
        if clampedTargetOffset <= topSnapThreshold {
            return 0
        }

        return clampedTargetOffset
    }
}
