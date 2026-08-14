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
        let sourceSnapshotID: UUID?
        let sectionGroupingSignature: SectionGroupingSignature
        let itemIDs: [UUID]
        let displayRows: [DisplayRow]
        let itemIndexByID: [UUID: Int]
        let primaryLabelTextByID: [UUID: String]
        let layoutIndex: ClipboardListLayoutIndex

        static let empty = DisplayCache(
            sourceSnapshotID: nil,
            sectionGroupingSignature: .current(),
            itemIDs: [],
            displayRows: [],
            itemIndexByID: [:],
            primaryLabelTextByID: [:],
            layoutIndex: .empty
        )

        func matches(
            sourceSnapshotID: UUID,
            referenceDate: Date = Date(),
            calendar: Calendar = .current
        ) -> Bool {
            self.sourceSnapshotID == sourceSnapshotID
                && sectionGroupingSignature
                    == SectionGroupingSignature(
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
        }

        func matches(
            items: [ClipboardItem],
            referenceDate: Date = Date(),
            calendar: Calendar = .current
        ) -> Bool {
            guard
                sectionGroupingSignature
                    == SectionGroupingSignature(
                        referenceDate: referenceDate,
                        calendar: calendar
                    )
            else {
                return false
            }

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
                items[cachedIndex].id == item.id
            {
                return cachedIndex
            }

            return items.firstIndex(where: { $0.id == item.id }) ?? 0
        }

        func itemExists(_ itemID: UUID, in items: [ClipboardItem]) -> Bool {
            if let cachedIndex = itemIndexByID[itemID],
                items.indices.contains(cachedIndex),
                items[cachedIndex].id == itemID
            {
                return true
            }

            return items.contains { $0.id == itemID }
        }

        func primaryLabelText(for item: ClipboardItem) -> String {
            primaryLabelTextByID[item.id] ?? ClipboardListStructure.primaryLabelText(for: item)
        }
    }

    struct SectionGroupingSignature: Equatable {
        let era: Int
        let yearForWeekOfYear: Int
        let weekOfYear: Int
        let dayOfYear: Int

        init(referenceDate: Date, calendar: Calendar) {
            self.era = calendar.component(.era, from: referenceDate)
            self.yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: referenceDate)
            self.weekOfYear = calendar.component(.weekOfYear, from: referenceDate)
            self.dayOfYear = calendar.ordinality(of: .day, in: .year, for: referenceDate) ?? 0
        }

        static func current() -> SectionGroupingSignature {
            SectionGroupingSignature(referenceDate: Date(), calendar: .current)
        }
    }

    static func makeDisplayCache(
        from items: [ClipboardItem],
        sourceSnapshotID: UUID? = nil,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DisplayCache {
        var primaryLabelTextByID: [UUID: String] = [:]
        primaryLabelTextByID.reserveCapacity(items.count)

        for item in items {
            primaryLabelTextByID[item.id] = primaryLabelText(for: item)
        }

        let displayRows = displayRows(from: items, referenceDate: referenceDate, calendar: calendar)
        let itemIndexByID = Dictionary(
            uniqueKeysWithValues: items.enumerated().map { index, item in
                (item.id, index)
            }
        )

        return DisplayCache(
            sourceSnapshotID: sourceSnapshotID,
            sectionGroupingSignature: SectionGroupingSignature(
                referenceDate: referenceDate,
                calendar: calendar
            ),
            itemIDs: items.map(\.id),
            displayRows: displayRows,
            itemIndexByID: itemIndexByID,
            primaryLabelTextByID: primaryLabelTextByID,
            layoutIndex: ClipboardListLayoutIndex(rows: displayRows, itemIndexByID: itemIndexByID)
        )
    }

    static func primaryLabelText(for item: ClipboardItem) -> String {
        ClipboardListSectionBuilder.primaryLabelText(for: item)
    }

    static func pinnedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        ClipboardListSectionBuilder.pinnedItems(from: items)
    }

    static func unpinnedSections(
        from items: [ClipboardItem],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ItemSection] {
        ClipboardListSectionBuilder.unpinnedSections(
            from: items,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func displayRows(
        from items: [ClipboardItem],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [DisplayRow] {
        ClipboardListSectionBuilder.displayRows(
            from: items,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    static func visibleItemIDs(
        in rows: [DisplayRow],
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        overscan: CGFloat
    ) -> [UUID] {
        ClipboardListRowGeometry.visibleItemIDs(
            in: rows,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            overscan: overscan
        )
    }

    static func estimatedContentHeight(for rows: [DisplayRow]) -> CGFloat {
        ClipboardListRowGeometry.estimatedContentHeight(for: rows)
    }

    static func estimatedMidY(forItemID itemID: UUID, in rows: [DisplayRow]) -> CGFloat? {
        ClipboardListRowGeometry.estimatedMidY(forItemID: itemID, in: rows)
    }

    static func estimatedFrame(forItemID itemID: UUID, in rows: [DisplayRow]) -> CGRect? {
        ClipboardListRowGeometry.estimatedFrame(forItemID: itemID, in: rows)
    }
}
