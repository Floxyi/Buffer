import Foundation

enum ClipboardListStructure {
    enum LayoutMetrics {
        static let contentPadding = CGFloat(8)
        static let rowSpacing = CGFloat(4)
        static let scrollbarWidth = CGFloat(4)
        static let itemRowHeight = CGFloat(44)
        static let sectionHeaderHeight = CGFloat(16)
        static let dividerHeight = CGFloat(9)
    }

    struct ItemSection: Identifiable {
        let id: String
        let title: String
        var items: [ClipboardItem]
    }

    struct DisplayRow: Identifiable {
        enum Kind {
            case header(title: String, systemImage: String?)
            case divider
            case item(ClipboardItem)
        }

        let id: String
        let kind: Kind
    }

    struct DisplayCache {
        let itemIDs: [UUID]
        let displayRows: [DisplayRow]
        let itemIndexByID: [UUID: Int]
        let primaryLabelTextByID: [UUID: String]

        static let empty = DisplayCache(
            itemIDs: [],
            displayRows: [],
            itemIndexByID: [:],
            primaryLabelTextByID: [:]
        )

        func matches(items: [ClipboardItem]) -> Bool {
            guard itemIDs.count == items.count else {
                return false
            }

            for index in items.indices {
                guard itemIDs[index] == items[index].id else {
                    return false
                }
            }

            return true
        }

        func index(for item: ClipboardItem, in items: [ClipboardItem]) -> Int {
            if let cachedIndex = itemIndexByID[item.id],
               items.indices.contains(cachedIndex),
               items[cachedIndex].id == item.id {
                return cachedIndex
            }

            return items.firstIndex(where: { $0.id == item.id }) ?? 0
        }

        func itemExists(_ itemID: UUID, in items: [ClipboardItem]) -> Bool {
            if let cachedIndex = itemIndexByID[itemID],
               items.indices.contains(cachedIndex),
               items[cachedIndex].id == itemID {
                return true
            }

            return items.contains { $0.id == itemID }
        }

        func primaryLabelText(for item: ClipboardItem) -> String {
            primaryLabelTextByID[item.id] ?? ClipboardListStructure.primaryLabelText(for: item)
        }
    }

    static func makeDisplayCache(from items: [ClipboardItem]) -> DisplayCache {
        var primaryLabelTextByID: [UUID: String] = [:]
        primaryLabelTextByID.reserveCapacity(items.count)

        for item in items {
            primaryLabelTextByID[item.id] = primaryLabelText(for: item)
        }

        return DisplayCache(
            itemIDs: items.map(\.id),
            displayRows: displayRows(from: items),
            itemIndexByID: Dictionary(
                uniqueKeysWithValues: items.enumerated().map { index, item in
                    (item.id, index)
                }
            ),
            primaryLabelTextByID: primaryLabelTextByID
        )
    }

    static func primaryLabelText(for item: ClipboardItem) -> String {
        ClipboardItemTypeRegistry.primaryLabelText(for: item)
    }

    static func pinnedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned)
    }

    static func unpinnedSections(from items: [ClipboardItem]) -> [ItemSection] {
        let unpinnedItems = items.filter { !$0.isPinned }
        guard !unpinnedItems.isEmpty else { return [] }

        var sections: [ItemSection] = []

        for item in unpinnedItems {
            let title = AppFormatting.historySectionTitle(for: item.timestamp)

            if let lastIndex = sections.indices.last,
               sections[lastIndex].title == title {
                sections[lastIndex].items.append(item)
            } else {
                sections.append(
                    ItemSection(
                        id: title,
                        title: title,
                        items: [item]
                    )
                )
            }
        }

        return sections
    }

    static func displayRows(from items: [ClipboardItem]) -> [DisplayRow] {
        let pinnedItems = pinnedItems(from: items)
        let unpinnedSections = unpinnedSections(from: items)

        var rows: [DisplayRow] = []
        rows.reserveCapacity(items.count + unpinnedSections.count + (pinnedItems.isEmpty ? 0 : 2))

        if !pinnedItems.isEmpty {
            rows.append(
                DisplayRow(
                    id: "header-pinned",
                    kind: .header(title: "PINNED", systemImage: nil)
                )
            )

            for item in pinnedItems {
                rows.append(
                    DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        for (sectionIndex, section) in unpinnedSections.enumerated() {
            if sectionIndex == 0 && !pinnedItems.isEmpty {
                rows.append(
                    DisplayRow(
                        id: "divider-pinned",
                        kind: .divider
                    )
                )
            }

            rows.append(
                DisplayRow(
                    id: "header-\(section.id)",
                    kind: .header(title: section.title, systemImage: nil)
                )
            )

            for item in section.items {
                rows.append(
                    DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        return rows
    }

    static func visibleItemIDs(
        in rows: [DisplayRow],
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
        var currentY = LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)
            let rowMinY = currentY
            let rowMaxY = currentY + rowHeight

            if rowMaxY >= visibleMinY, rowMinY <= visibleMaxY {
                if case .item(let item) = row.kind {
                    result.append(item.id)
                }
            }

            if rowMinY > visibleMaxY {
                break
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += LayoutMetrics.rowSpacing
            }
        }

        return result
    }

    static func estimatedContentHeight(for rows: [DisplayRow]) -> CGFloat {
        guard !rows.isEmpty else {
            return 2 * LayoutMetrics.contentPadding
        }

        let rowsHeight = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + estimatedRowHeight(for: row)
        }
        let spacingHeight = CGFloat(max(0, rows.count - 1)) * LayoutMetrics.rowSpacing

        return 2 * LayoutMetrics.contentPadding + rowsHeight + spacingHeight
    }

    static func estimatedMidY(forItemID itemID: UUID, in rows: [DisplayRow]) -> CGFloat? {
        guard !rows.isEmpty else { return nil }

        var currentY = LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)

            if case .item(let item) = row.kind, item.id == itemID {
                return currentY + rowHeight / 2
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += LayoutMetrics.rowSpacing
            }
        }

        return nil
    }

    static func estimatedFrame(forItemID itemID: UUID, in rows: [DisplayRow]) -> CGRect? {
        guard !rows.isEmpty else { return nil }

        var currentY = LayoutMetrics.contentPadding

        for (index, row) in rows.enumerated() {
            let rowHeight = estimatedRowHeight(for: row)

            if case .item(let item) = row.kind, item.id == itemID {
                return CGRect(
                    x: 0,
                    y: currentY,
                    width: 0,
                    height: rowHeight
                )
            }

            currentY += rowHeight

            if index < rows.count - 1 {
                currentY += LayoutMetrics.rowSpacing
            }
        }

        return nil
    }

    private static func estimatedRowHeight(for row: DisplayRow) -> CGFloat {
        switch row.kind {
        case .header:
            return LayoutMetrics.sectionHeaderHeight
        case .divider:
            return LayoutMetrics.dividerHeight
        case .item:
            return LayoutMetrics.itemRowHeight
        }
    }
}
