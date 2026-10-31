import Foundation

enum ClipboardListSectionBuilder {
    static func primaryLabelText(for item: ClipboardItem) -> String {
        ClipboardItemPresentation.primaryLabelText(for: item)
    }

    static func pinnedItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned)
    }

    static func unpinnedSections(
        from items: [ClipboardItem],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardListStructure.ItemSection] {
        let unpinnedItems = items.filter { !$0.isPinned }
        guard !unpinnedItems.isEmpty else { return [] }

        var sections: [ClipboardListStructure.ItemSection] = []

        for item in unpinnedItems {
            let title = AppFormatting.historySectionTitle(
                for: item.timestamp,
                calendar: calendar,
                referenceDate: referenceDate
            )

            if let lastIndex = sections.indices.last,
                sections[lastIndex].title == title
            {
                sections[lastIndex].items.append(item)
            } else {
                sections.append(
                    ClipboardListStructure.ItemSection(
                        id: title,
                        title: title,
                        items: [item]
                    )
                )
            }
        }

        return sections
    }

    static func displayRows(
        from items: [ClipboardItem],
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ClipboardListStructure.DisplayRow] {
        let pinnedItems = pinnedItems(from: items)
        let unpinnedSections = unpinnedSections(
            from: items,
            referenceDate: referenceDate,
            calendar: calendar
        )

        var rows: [ClipboardListStructure.DisplayRow] = []
        rows.reserveCapacity(items.count + unpinnedSections.count + (pinnedItems.isEmpty ? 0 : 2))

        if !pinnedItems.isEmpty {
            rows.append(
                ClipboardListStructure.DisplayRow(
                    id: "header-pinned",
                    kind: .header(title: String(localized: "PINNED"), systemImage: nil)
                )
            )

            for item in pinnedItems {
                rows.append(
                    ClipboardListStructure.DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        for (sectionIndex, section) in unpinnedSections.enumerated() {
            if sectionIndex == 0 && !pinnedItems.isEmpty {
                rows.append(
                    ClipboardListStructure.DisplayRow(
                        id: "divider-pinned",
                        kind: .divider
                    )
                )
            }

            rows.append(
                ClipboardListStructure.DisplayRow(
                    id: "header-\(section.id)",
                    kind: .header(title: section.title, systemImage: nil)
                )
            )

            for item in section.items {
                rows.append(
                    ClipboardListStructure.DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        return rows
    }

    static func displayRowsCancellable(
        from items: [ClipboardItem],
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [ClipboardListStructure.DisplayRow] {
        var pinnedItems: [ClipboardItem] = []
        var unpinnedSections: [ClipboardListStructure.ItemSection] = []
        pinnedItems.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            if item.isPinned {
                pinnedItems.append(item)
                continue
            }
            let title = AppFormatting.historySectionTitle(
                for: item.timestamp,
                calendar: calendar,
                referenceDate: referenceDate
            )
            if let lastIndex = unpinnedSections.indices.last,
                unpinnedSections[lastIndex].title == title
            {
                unpinnedSections[lastIndex].items.append(item)
            } else {
                unpinnedSections.append(.init(id: title, title: title, items: [item]))
            }
        }

        var rows: [ClipboardListStructure.DisplayRow] = []
        rows.reserveCapacity(items.count + unpinnedSections.count + (pinnedItems.isEmpty ? 0 : 2))
        if !pinnedItems.isEmpty {
            rows.append(.init(id: "header-pinned", kind: .header(title: String(localized: "PINNED"), systemImage: nil)))
            for (index, item) in pinnedItems.enumerated() {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                rows.append(.init(id: "item-\(item.id.uuidString)", kind: .item(item)))
            }
        }
        for (sectionIndex, section) in unpinnedSections.enumerated() {
            try Task.checkCancellation()
            if sectionIndex == 0, !pinnedItems.isEmpty {
                rows.append(.init(id: "divider-pinned", kind: .divider))
            }
            rows.append(.init(id: "header-\(section.id)", kind: .header(title: section.title, systemImage: nil)))
            for (index, item) in section.items.enumerated() {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                rows.append(.init(id: "item-\(item.id.uuidString)", kind: .item(item)))
            }
        }
        return rows
    }
}
