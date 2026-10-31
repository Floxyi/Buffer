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

    struct ItemSection: Identifiable, Sendable {
        let id: String
        let title: String
        var items: [ClipboardItem]
    }

    struct DisplayRow: Identifiable, Sendable {
        enum Kind: Sendable {
            case header(title: String, systemImage: String?)
            case divider
            case item(ClipboardItem)
        }

        let id: String
        let kind: Kind
    }

    struct DisplayCache: Sendable {
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
            assertionFailure("Display cache is inconsistent with the published item snapshot")
            return 0
        }

        func itemExists(_ itemID: UUID, in items: [ClipboardItem]) -> Bool {
            if let cachedIndex = itemIndexByID[itemID],
                items.indices.contains(cachedIndex),
                items[cachedIndex].id == itemID
            {
                return true
            }

            assertionFailure("Display cache is inconsistent with the published item snapshot")
            return false
        }

        func primaryLabelText(for item: ClipboardItem) -> String {
            guard let text = primaryLabelTextByID[item.id] else {
                assertionFailure("Display cache is missing a primary label")
                return ""
            }
            return text
        }
    }

    struct SectionGroupingSignature: Equatable, Sendable {
        let era: Int
        let yearForWeekOfYear: Int
        let weekOfYear: Int
        let dayOfYear: Int
        let calendarIdentifier: String
        let timeZoneIdentifier: String

        init(referenceDate: Date, calendar: Calendar) {
            self.era = calendar.component(.era, from: referenceDate)
            self.yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: referenceDate)
            self.weekOfYear = calendar.component(.weekOfYear, from: referenceDate)
            self.dayOfYear = calendar.ordinality(of: .day, in: .year, for: referenceDate) ?? 0
            self.calendarIdentifier = String(describing: calendar.identifier)
            self.timeZoneIdentifier = calendar.timeZone.identifier
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
        makeDisplayCache(
            from: items,
            sourceSnapshotID: sourceSnapshotID,
            referenceDate: referenceDate,
            calendar: calendar,
            checkCancellation: { _ in },
            makeRows: {
                displayRows(from: items, referenceDate: referenceDate, calendar: calendar)
            },
            makeLayoutIndex: { rows, itemIndexByID in
                ClipboardListLayoutIndex(rows: rows, itemIndexByID: itemIndexByID)
            }
        )
    }

    static func makeDisplayCacheCancellable(
        from items: [ClipboardItem],
        sourceSnapshotID: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> DisplayCache {
        try makeDisplayCache(
            from: items,
            sourceSnapshotID: sourceSnapshotID,
            referenceDate: referenceDate,
            calendar: calendar,
            checkCancellation: { index in
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
            },
            makeRows: {
                try ClipboardListSectionBuilder.displayRowsCancellable(
                    from: items,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            },
            makeLayoutIndex: { rows, itemIndexByID in
                try ClipboardListLayoutIndex(
                    cancellableRows: rows,
                    itemIndexByID: itemIndexByID
                )
            }
        )
    }

    private static func makeDisplayCache(
        from items: [ClipboardItem],
        sourceSnapshotID: UUID?,
        referenceDate: Date,
        calendar: Calendar,
        checkCancellation: (Int) throws -> Void,
        makeRows: () throws -> [DisplayRow],
        makeLayoutIndex: ([DisplayRow], [UUID: Int]) throws -> ClipboardListLayoutIndex
    ) rethrows -> DisplayCache {
        var primaryLabelTextByID: [UUID: String] = [:]
        var itemIndexByID: [UUID: Int] = [:]
        var itemIDs: [UUID] = []
        primaryLabelTextByID.reserveCapacity(items.count)
        itemIndexByID.reserveCapacity(items.count)
        itemIDs.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            try checkCancellation(index)
            primaryLabelTextByID[item.id] = primaryLabelText(for: item)
            itemIndexByID[item.id] = index
            itemIDs.append(item.id)
        }
        let displayRows = try makeRows()
        return DisplayCache(
            sourceSnapshotID: sourceSnapshotID,
            sectionGroupingSignature: SectionGroupingSignature(
                referenceDate: referenceDate,
                calendar: calendar
            ),
            itemIDs: itemIDs,
            displayRows: displayRows,
            itemIndexByID: itemIndexByID,
            primaryLabelTextByID: primaryLabelTextByID,
            layoutIndex: try makeLayoutIndex(displayRows, itemIndexByID)
        )
    }

    static func makeSearchDisplayCacheCancellable(
        from items: [ClipboardItem],
        similarItemIDs: Set<UUID>,
        sourceSnapshotID: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> DisplayCache {
        var primaryLabelTextByID: [UUID: String] = [:]
        var itemIndexByID: [UUID: Int] = [:]
        var itemIDs: [UUID] = []
        var displayRows: [DisplayRow] = []
        primaryLabelTextByID.reserveCapacity(items.count)
        itemIndexByID.reserveCapacity(items.count)
        itemIDs.reserveCapacity(items.count)
        displayRows.reserveCapacity(items.count + (similarItemIDs.isEmpty ? 0 : 1))

        var insertedSimilarHeader = false
        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            if similarItemIDs.contains(item.id), !insertedSimilarHeader {
                displayRows.append(
                    DisplayRow(
                        id: "search-region-similar",
                        kind: .header(
                            title: String(localized: "Similar Matches"),
                            systemImage: "text.magnifyingglass"
                        )
                    )
                )
                insertedSimilarHeader = true
            }
            primaryLabelTextByID[item.id] = primaryLabelText(for: item)
            itemIndexByID[item.id] = index
            itemIDs.append(item.id)
            displayRows.append(
                DisplayRow(
                    id: clipboardListScrollID(for: item.id),
                    kind: .item(item)
                )
            )
        }

        return DisplayCache(
            sourceSnapshotID: sourceSnapshotID,
            sectionGroupingSignature: SectionGroupingSignature(
                referenceDate: referenceDate,
                calendar: calendar
            ),
            itemIDs: itemIDs,
            displayRows: displayRows,
            itemIndexByID: itemIndexByID,
            primaryLabelTextByID: primaryLabelTextByID,
            layoutIndex: try ClipboardListLayoutIndex(
                cancellableRows: displayRows,
                itemIndexByID: itemIndexByID
            )
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
