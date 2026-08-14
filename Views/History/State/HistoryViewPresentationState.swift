import Foundation

enum HistoryDateFilterPreset: String, CaseIterable, Identifiable, Sendable {
    case allDates
    case today
    case yesterday
    case last7Days
    case last30Days

    var id: Self { self }

    static let selectableCases = allCases.filter { $0 != .allDates }

    var displayName: String {
        switch self {
        case .allDates: String(localized: "All Dates")
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .last7Days: String(localized: "Last 7 Days")
        case .last30Days: String(localized: "Last 30 Days")
        }
    }

    func dateInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        let dayOffsets: (start: Int, end: Int)
        switch self {
        case .allDates:
            return nil
        case .today:
            dayOffsets = (0, 1)
        case .yesterday:
            dayOffsets = (-1, 0)
        case .last7Days:
            dayOffsets = (-6, 1)
        case .last30Days:
            dayOffsets = (-29, 1)
        }

        let today = calendar.startOfDay(for: date)
        guard
            let start = calendar.date(byAdding: .day, value: dayOffsets.start, to: today),
            let end = calendar.date(byAdding: .day, value: dayOffsets.end, to: today)
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
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
    var datePreset = HistoryDateFilterPreset.allDates

    var isEmpty: Bool {
        !isBookmarkedOnly
            && selectedApplication == nil
            && selectedKind == nil
            && datePreset == .allDates
    }

    func clipboardFilters(now: Date, calendar: Calendar) -> ClipboardFilters {
        ClipboardFilters(
            requiresBookmark: isBookmarkedOnly,
            sourceBundleIdentifiers: selectedApplication.map { [$0.bundleIdentifier] } ?? [],
            kinds: selectedKind.map { [$0] } ?? [],
            copiedAt: datePreset.dateInterval(containing: now, calendar: calendar)
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

    init(filterState: HistoryFilterState, hasApplicationOptions: Bool) {
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
            title: filterState.datePreset == .allDates
                ? String(localized: "Date") : filterState.datePreset.displayName,
            accessibilityLabel: String(localized: "Date Filter"),
            accessibilityValue: filterState.datePreset.displayName,
            accessibilityIdentifier: "historyFilter.date",
            isActive: filterState.datePreset != .allDates,
            isEnabled: true
        )
    }
}

enum HistoryApplicationFilterOptions {
    static func make(
        from items: [ClipboardItem],
        retaining selectedApplication: HistoryApplicationFilterOption? = nil
    ) -> [HistoryApplicationFilterOption] {
        var newestItemByBundleIdentifier: [String: ClipboardItem] = [:]
        for item in items {
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
