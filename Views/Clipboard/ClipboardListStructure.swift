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
