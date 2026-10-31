import Foundation

struct HistoryCalendarDay: Hashable, Comparable, Sendable {
    let era: Int
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        era = components.era ?? 1
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    init(era: Int = 1, year: Int, month: Int, day: Int) {
        self.era = era
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.era, lhs.year, lhs.month, lhs.day)
            < (rhs.era, rhs.year, rhs.month, rhs.day)
    }

    func date(in calendar: Calendar) -> Date? {
        guard
            let date = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    era: era,
                    year: year,
                    month: month,
                    day: day
                )
            )
        else { return nil }
        return calendar.startOfDay(for: date)
    }
}

struct HistoryDateFilterSelection: Equatable, Sendable {
    let startDay: HistoryCalendarDay
    let endDay: HistoryCalendarDay

    init(startDay: HistoryCalendarDay, endDay: HistoryCalendarDay) {
        if startDay <= endDay {
            self.startDay = startDay
            self.endDay = endDay
        } else {
            self.startDay = endDay
            self.endDay = startDay
        }
    }

    init(day: HistoryCalendarDay) {
        self.init(startDay: day, endDay: day)
    }

    var isSingleDay: Bool {
        startDay == endDay
    }

    func contains(_ day: HistoryCalendarDay) -> Bool {
        day >= startDay && day <= endDay
    }

    func dateInterval(calendar: Calendar) -> DateInterval? {
        guard let start = startDay.date(in: calendar),
            let inclusiveEnd = endDay.date(in: calendar),
            let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd)
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    func displayName(calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        guard let start = startDay.date(in: calendar), let end = endDay.date(in: calendar) else {
            return String(localized: "Date")
        }
        if isSingleDay {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: start)
        }
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }
}

struct HistoryDateAvailability: Equatable, Sendable {
    static let empty = Self(copiedDays: [])

    let copiedDays: Set<HistoryCalendarDay>
    let earliestDay: HistoryCalendarDay?
    let latestDay: HistoryCalendarDay?

    init(copiedDays: Set<HistoryCalendarDay>) {
        self.copiedDays = copiedDays
        earliestDay = copiedDays.min()
        latestDay = copiedDays.max()
    }

    static func make(
        from items: [ClipboardItem],
        calendar: Calendar,
        checkCancellation: ((Int) throws -> Void)? = nil
    ) rethrows -> Self {
        var copiedDays: Set<HistoryCalendarDay> = []
        copiedDays.reserveCapacity(min(items.count, 366))
        for (index, item) in items.enumerated() {
            try checkCancellation?(index)
            copiedDays.insert(HistoryCalendarDay(date: item.timestamp, calendar: calendar))
        }
        return Self(copiedDays: copiedDays)
    }

    func normalizedSelection(_ selection: HistoryDateFilterSelection) -> HistoryDateFilterSelection? {
        let containedDays = copiedDays.filter(selection.contains)
        guard let startDay = containedDays.min(), let endDay = containedDays.max() else {
            return nil
        }
        return HistoryDateFilterSelection(startDay: startDay, endDay: endDay)
    }
}

struct HistoryApplicationFilterOption: Identifiable, Equatable, Sendable {
    let bundleIdentifier: String
    let displayName: String
    let iconItem: ClipboardItem

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        displayName: String,
        representativeItem: ClipboardItem
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        // Retain only the source metadata needed by the shared icon loader. A
        // type-neutral item also lets apps represented solely by email clips
        // participate in the filter menu without changing row icon policy.
        iconItem = ClipboardItem(
            id: representativeItem.id,
            timestamp: representativeItem.timestamp,
            sourceApp: representativeItem.sourceApp,
            sourceAppBundleIdentifier: representativeItem.sourceAppBundleIdentifier,
            sourceAppBundlePath: representativeItem.sourceAppBundlePath,
            content: .text(TextItemContent(inlineText: ""))
        )
    }
}

struct HistoryFilterState: Equatable, Sendable {
    var isBookmarkedOnly = false
    var selectedApplication: HistoryApplicationFilterOption?
    var selectedKind: ClipboardItemKind?
    var dateSelection: HistoryDateFilterSelection?

    var isEmpty: Bool {
        !isBookmarkedOnly
            && selectedApplication == nil
            && selectedKind == nil
            && dateSelection == nil
    }

    func clipboardFilters(calendar: Calendar) -> ClipboardFilters {
        ClipboardFilters(
            requiresBookmark: isBookmarkedOnly,
            sourceBundleIdentifiers: selectedApplication.map { [$0.bundleIdentifier] } ?? [],
            kinds: selectedKind.map { [$0] } ?? [],
            copiedAt: dateSelection?.dateInterval(calendar: calendar)
        )
    }
}

struct HistoryFilterControlPresentation: Equatable, Sendable {
    let title: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let isActive: Bool
    let isEnabled: Bool
}

struct HistoryFilterBarPresentation: Equatable, Sendable {
    let bookmarks: HistoryFilterControlPresentation
    let application: HistoryFilterControlPresentation
    let kind: HistoryFilterControlPresentation
    let date: HistoryFilterControlPresentation

    init(
        filterState: HistoryFilterState,
        hasApplicationOptions: Bool,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        bookmarks = HistoryFilterControlPresentation(
            title: String(localized: "Bookmarks"),
            accessibilityLabel: String(localized: "Bookmarks Filter"),
            accessibilityValue: filterState.isBookmarkedOnly
                ? String(localized: "Bookmarked items only") : String(localized: "All items"),
            accessibilityIdentifier: "historyFilter.bookmarks",
            isActive: filterState.isBookmarkedOnly,
            isEnabled: true
        )

        application = HistoryFilterControlPresentation(
            title: filterState.selectedApplication?.displayName ?? String(localized: "App"),
            accessibilityLabel: String(localized: "Application Filter"),
            accessibilityValue: filterState.selectedApplication?.displayName
                ?? String(localized: "All applications"),
            accessibilityIdentifier: "historyFilter.app",
            isActive: filterState.selectedApplication != nil,
            isEnabled: hasApplicationOptions
        )

        let kindDefinition = filterState.selectedKind.map(
            ClipboardItemPresentation.definition(for:)
        )
        kind = HistoryFilterControlPresentation(
            title: kindDefinition?.displayName ?? String(localized: "Type"),
            accessibilityLabel: String(localized: "Item Type Filter"),
            accessibilityValue: kindDefinition?.displayName ?? String(localized: "All types"),
            accessibilityIdentifier: "historyFilter.type",
            isActive: filterState.selectedKind != nil,
            isEnabled: true
        )

        date = HistoryFilterControlPresentation(
            title: filterState.dateSelection?.displayName(calendar: calendar)
                ?? String(localized: "Date"),
            accessibilityLabel: String(localized: "Date Filter"),
            accessibilityValue: filterState.dateSelection?.displayName(calendar: calendar)
                ?? String(localized: "All Dates"),
            accessibilityIdentifier: "historyFilter.date",
            isActive: filterState.dateSelection != nil,
            isEnabled: true
        )
    }
}

enum HistoryApplicationFilterOptions {
    static func make(
        from items: [ClipboardItem],
        retaining selectedApplication: HistoryApplicationFilterOption? = nil,
        checkCancellation: ((Int) throws -> Void)? = nil
    ) rethrows -> [HistoryApplicationFilterOption] {
        var newestItemByBundleIdentifier: [String: ClipboardItem] = [:]
        for (index, item) in items.enumerated() {
            try checkCancellation?(index)
            guard let bundleIdentifier = item.normalizedSourceAppBundleIdentifier else {
                continue
            }

            if let existing = newestItemByBundleIdentifier[bundleIdentifier],
                existing.timestamp >= item.timestamp
            {
                continue
            }
            newestItemByBundleIdentifier[bundleIdentifier] = item
        }

        var options = newestItemByBundleIdentifier.map { bundleIdentifier, item in
            HistoryApplicationFilterOption(
                bundleIdentifier: bundleIdentifier,
                displayName: item.sourceAppDisplayName ?? bundleIdentifier,
                representativeItem: item
            )
        }
        if let selectedApplication,
            newestItemByBundleIdentifier[selectedApplication.bundleIdentifier] == nil
        {
            options.append(selectedApplication)
        }

        return options.sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }
}

struct HistoryViewPresentationState {
    var showsQuickPasteNumbers = false
    var windowOpenToken = 0
    var shouldFocusSearchOnOpen = true
    var searchSelectionToken = 0
    var openListScrollRequest = HistoryOpenListScrollRequest(mode: .scrollToTop)
    var openListScrollRequestToken = 0
    var jumpToHistoryState = HistoryJumpToHistoryState.idle
}
