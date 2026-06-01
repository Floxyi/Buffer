import CoreGraphics
import Foundation

enum ClipboardListRowGeometry {
    static func visibleItemIDs(
        in rows: [ClipboardListStructure.DisplayRow],
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        overscan: CGFloat
    ) -> [UUID] {
        guard viewportHeight > 0 else {
            return []
        }

        let visibleMinY = max(0, scrollOffset - overscan)
        let visibleMaxY = scrollOffset + viewportHeight + overscan

        var result: [UUID] = []
        var currentY = ClipboardListStructure.LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)
            let rowMinY = currentY
            let rowMaxY = currentY + rowHeight

            if rowMaxY >= visibleMinY, rowMinY <= visibleMaxY,
               case .item(let item) = row.kind {
                result.append(item.id)
            }

            if rowMinY > visibleMaxY {
                break
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += ClipboardListStructure.LayoutMetrics.rowSpacing
            }
        }

        return result
    }

    static func estimatedContentHeight(for rows: [ClipboardListStructure.DisplayRow]) -> CGFloat {
        guard !rows.isEmpty else {
            return 2 * ClipboardListStructure.LayoutMetrics.contentPadding
        }

        let rowsHeight = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + estimatedRowHeight(for: row)
        }
        let spacingHeight = CGFloat(max(0, rows.count - 1)) * ClipboardListStructure.LayoutMetrics.rowSpacing

        return 2 * ClipboardListStructure.LayoutMetrics.contentPadding + rowsHeight + spacingHeight
    }

    static func estimatedMidY(
        forItemID itemID: UUID,
        in rows: [ClipboardListStructure.DisplayRow]
    ) -> CGFloat? {
        guard !rows.isEmpty else { return nil }

        var currentY = ClipboardListStructure.LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)

            if case .item(let item) = row.kind, item.id == itemID {
                return currentY + rowHeight / 2
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += ClipboardListStructure.LayoutMetrics.rowSpacing
            }
        }

        return nil
    }

    static func estimatedFrame(
        forItemID itemID: UUID,
        in rows: [ClipboardListStructure.DisplayRow]
    ) -> CGRect? {
        guard !rows.isEmpty else { return nil }

        var currentY = ClipboardListStructure.LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)

            if case .item(let item) = row.kind, item.id == itemID {
                return CGRect(x: 0, y: currentY, width: 0, height: rowHeight)
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += ClipboardListStructure.LayoutMetrics.rowSpacing
            }
        }

        return nil
    }

    static func estimatedRowHeight(for row: ClipboardListStructure.DisplayRow) -> CGFloat {
        switch row.kind {
        case .header:
            return ClipboardListStructure.LayoutMetrics.sectionHeaderHeight
        case .divider:
            return ClipboardListStructure.LayoutMetrics.dividerHeight
        case .item:
            return ClipboardListStructure.LayoutMetrics.itemRowHeight
        }
    }
}
