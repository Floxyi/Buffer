import CoreGraphics
import Foundation

/// Immutable geometry derived from the display rows. Interactive scrolling must use
/// this index instead of walking every row above the viewport.
struct ClipboardListLayoutIndex {
    struct ItemEntry {
        let id: UUID
        let itemIndex: Int
        let frame: CGRect
    }

    let contentHeight: CGFloat
    let entries: [ItemEntry]
    private let frameByItemID: [UUID: CGRect]

    static let empty = ClipboardListLayoutIndex(rows: [], itemIndexByID: [:])

    init(
        rows: [ClipboardListStructure.DisplayRow],
        itemIndexByID: [UUID: Int]
    ) {
        var entries: [ItemEntry] = []
        entries.reserveCapacity(itemIndexByID.count)
        var frames: [UUID: CGRect] = [:]
        frames.reserveCapacity(itemIndexByID.count)

        var currentY = ClipboardListStructure.LayoutMetrics.contentPadding
        for (rowIndex, row) in rows.enumerated() {
            let height = ClipboardListRowGeometry.estimatedRowHeight(for: row)
            if case .item(let item) = row.kind,
                let itemIndex = itemIndexByID[item.id]
            {
                let frame = CGRect(x: 0, y: currentY, width: 0, height: height)
                entries.append(ItemEntry(id: item.id, itemIndex: itemIndex, frame: frame))
                frames[item.id] = frame
            }

            currentY += height
            if rowIndex < rows.count - 1 {
                currentY += ClipboardListStructure.LayoutMetrics.rowSpacing
            }
        }

        self.entries = entries
        self.frameByItemID = frames
        self.contentHeight =
            rows.isEmpty
            ? 2 * ClipboardListStructure.LayoutMetrics.contentPadding
            : currentY + ClipboardListStructure.LayoutMetrics.contentPadding
    }

    func frame(for itemID: UUID) -> CGRect? {
        frameByItemID[itemID]
    }

    func midY(for itemID: UUID) -> CGFloat? {
        frameByItemID[itemID]?.midY
    }

    func visibleItemEntries(
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        overscan: CGFloat = 0
    ) -> ArraySlice<ItemEntry> {
        guard viewportHeight > 0, !entries.isEmpty else { return [] }

        let minimumY = max(0, scrollOffset - overscan)
        let maximumY = scrollOffset + viewportHeight + overscan
        var lower = 0
        var upper = entries.count

        // Find the first item whose bottom edge intersects the requested range.
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if entries[middle].frame.maxY < minimumY {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let start = lower
        while upper < entries.count, entries[upper].frame.minY <= maximumY {
            upper += 1
        }
        return entries[start..<upper]
    }

    func visibleItemIDs(
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        overscan: CGFloat = 0
    ) -> [UUID] {
        visibleItemEntries(
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: overscan
        ).map(\.id)
    }
}

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
                case .item(let item) = row.kind
            {
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
