import SwiftUI

struct HistoryDateFilterControl: View {
    let title: String
    let selection: HistoryDateFilterSelection?
    let availability: HistoryDateAvailability
    let calendar: Calendar
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let onApply: @MainActor @Sendable (HistoryDateFilterSelection?) -> Void

    @State private var isPresented = false

    private var isEnabled: Bool {
        !availability.copiedDays.isEmpty || selection != nil
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                isPresented.toggle()
            } label: {
                HistoryFilterControlLabel(
                    title: title,
                    symbolName: "calendar",
                    showsMenuChevron: true,
                    isExpanded: isPresented,
                    trailingAccessoryWidth: selection == nil ? 0 : 26
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
            .background {
                HistoryAnchoredPopover(isPresented: $isPresented) {
                    HistoryDatePickerPopover(
                        committedSelection: selection,
                        availability: availability,
                        calendar: calendar,
                        onCancel: { isPresented = false },
                        onApply: { nextSelection in
                            onApply(nextSelection)
                            isPresented = false
                        }
                    )
                }
            }

            if selection != nil {
                HistoryFilterClearButton(
                    accessibilityLabel: String(localized: "Clear Date Filter"),
                    accessibilityIdentifier: "historyFilter.date.clear"
                ) {
                    onApply(nil)
                }
            }
        }
        .historyFilterControlSurface(isActive: selection != nil)
        .opacity(isEnabled ? 1 : 0.45)
        .help(String(localized: "Filter by copied date"))
    }
}

struct HistoryDatePickerDraft: Equatable, Sendable {
    private(set) var selection: HistoryDateFilterSelection?
    private(set) var anchorDay: HistoryCalendarDay?

    init(committedSelection: HistoryDateFilterSelection?) {
        selection = committedSelection
        anchorDay =
            committedSelection?.isSingleDay == true
            ? committedSelection?.startDay
            : nil
    }

    mutating func select(_ day: HistoryCalendarDay) {
        if let anchorDay {
            selection = HistoryDateFilterSelection(startDay: anchorDay, endDay: day)
            self.anchorDay = nil
        } else {
            selection = HistoryDateFilterSelection(day: day)
            anchorDay = day
        }
    }

    func preview(hoveredDay: HistoryCalendarDay?) -> HistoryDateFilterSelection? {
        guard let anchorDay, let hoveredDay else { return selection }
        return HistoryDateFilterSelection(startDay: anchorDay, endDay: hoveredDay)
    }
}

struct HistoryCalendarMonth: Equatable, Sendable {
    let firstDay: HistoryCalendarDay
    let days: [HistoryCalendarDay?]

    init?(containing day: HistoryCalendarDay, calendar: Calendar) {
        guard let dayDate = day.date(in: calendar),
            let monthInterval = calendar.dateInterval(of: .month, for: dayDate),
            let dayRange = calendar.range(of: .day, in: .month, for: monthInterval.start)
        else { return nil }

        firstDay = HistoryCalendarDay(date: monthInterval.start, calendar: calendar)
        let weekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingCount = (weekday - calendar.firstWeekday + 7) % 7
        var grid = [HistoryCalendarDay?](repeating: nil, count: 42)
        for dayNumber in dayRange {
            guard
                let date = calendar.date(
                    byAdding: .day,
                    value: dayNumber - 1,
                    to: monthInterval.start
                )
            else { continue }
            let index = leadingCount + dayNumber - 1
            guard grid.indices.contains(index) else { continue }
            grid[index] = HistoryCalendarDay(date: date, calendar: calendar)
        }
        days = grid
    }

    func addingMonths(_ value: Int, calendar: Calendar) -> Self? {
        guard let firstDate = firstDay.date(in: calendar),
            let nextDate = calendar.date(byAdding: .month, value: value, to: firstDate)
        else { return nil }
        return Self(containing: HistoryCalendarDay(date: nextDate, calendar: calendar), calendar: calendar)
    }
}

private struct HistoryDatePickerPopover: View {
    let committedSelection: HistoryDateFilterSelection?
    let availability: HistoryDateAvailability
    let calendar: Calendar
    let onCancel: @MainActor @Sendable () -> Void
    let onApply: @MainActor @Sendable (HistoryDateFilterSelection) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: HistoryDatePickerDraft
    @State private var visibleMonth: HistoryCalendarMonth
    @State private var hoveredDay: HistoryCalendarDay?
    @FocusState private var focusedDay: HistoryCalendarDay?

    init(
        committedSelection: HistoryDateFilterSelection?,
        availability: HistoryDateAvailability,
        calendar: Calendar,
        onCancel: @escaping @MainActor @Sendable () -> Void,
        onApply: @escaping @MainActor @Sendable (HistoryDateFilterSelection) -> Void
    ) {
        self.committedSelection = committedSelection
        self.availability = availability
        self.calendar = calendar
        self.onCancel = onCancel
        self.onApply = onApply

        let initialDay =
            committedSelection?.endDay
            ?? availability.latestDay
            ?? HistoryCalendarDay(date: Date(), calendar: calendar)
        let initialMonth =
            HistoryCalendarMonth(containing: initialDay, calendar: calendar)
            ?? HistoryCalendarMonth(
                containing: HistoryCalendarDay(date: Date(), calendar: calendar),
                calendar: calendar
            )!
        _draft = State(initialValue: HistoryDatePickerDraft(committedSelection: committedSelection))
        _visibleMonth = State(initialValue: initialMonth)
    }

    private var previewSelection: HistoryDateFilterSelection? {
        draft.preview(hoveredDay: hoveredDay)
    }

    private var canNavigateBackward: Bool {
        guard let earliestDay = availability.earliestDay,
            let earliestMonth = HistoryCalendarMonth(containing: earliestDay, calendar: calendar)
        else { return false }
        return visibleMonth.firstDay > earliestMonth.firstDay
    }

    private var canNavigateForward: Bool {
        guard let latestDay = availability.latestDay,
            let latestMonth = HistoryCalendarMonth(containing: latestDay, calendar: calendar)
        else { return false }
        return visibleMonth.firstDay < latestMonth.firstDay
    }

    var body: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
                .padding(.top, 10)
            calendarGrid
                .padding(.top, 4)
            Divider()
                .padding(.top, 10)
            footer
                .padding(.top, 10)
        }
        .padding(12)
        .frame(width: 304)
        .onAppear {
            focusedDay = draft.selection?.endDay ?? availability.latestDay
        }
        .onExitCommand(perform: onCancel)
        .onKeyPress(.pageUp) {
            navigateMonth(by: -1)
            return .handled
        }
        .onKeyPress(.pageDown) {
            navigateMonth(by: 1)
            return .handled
        }
        .onMoveCommand(perform: moveFocus(_:))
        .accessibilityElement(children: .contain)
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(monthTitle)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HistoryDatePickerNavigationButton(
                symbolName: "chevron.left",
                accessibilityLabel: String(localized: "Previous month"),
                isEnabled: canNavigateBackward
            ) {
                navigateMonth(by: -1)
            }

            HistoryDatePickerNavigationButton(
                symbolName: "chevron.right",
                accessibilityLabel: String(localized: "Next month"),
                isEnabled: canNavigateForward
            ) {
                navigateMonth(by: 1)
            }
        }
        .foregroundStyle(.primary)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarGrid: some View {
        ZStack {
            HistoryDateRangeLayer(segments: rangeSegments)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(),
                        spacing: HistoryDatePickerLayout.columnSpacing
                    ),
                    count: HistoryDatePickerLayout.columnCount
                ),
                spacing: HistoryDatePickerLayout.rowSpacing
            ) {
                ForEach(visibleMonth.days.indices, id: \.self) { index in
                    if let day = visibleMonth.days[index] {
                        dayButton(day)
                    } else {
                        Color.clear
                            .frame(height: HistoryDatePickerLayout.dayHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(height: HistoryDatePickerLayout.gridHeight)
        .onHover { isInside in
            if !isInside {
                hoveredDay = nil
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: previewSelection)
    }

    private var rangeSegments: [HistoryDateRangeSegment] {
        guard let selection = previewSelection else { return [] }

        return (0..<HistoryDatePickerLayout.rowCount).compactMap { row in
            let startIndex = row * HistoryDatePickerLayout.columnCount
            let endIndex = startIndex + HistoryDatePickerLayout.columnCount
            let selectedDays = visibleMonth.days[startIndex..<endIndex].enumerated().compactMap {
                column,
                day -> (column: Int, day: HistoryCalendarDay)? in
                guard let day, selection.contains(day) else { return nil }
                return (column, day)
            }
            guard let first = selectedDays.first,
                let last = selectedDays.last
            else { return nil }
            return HistoryDateRangeSegment(
                row: row,
                firstColumn: first.column,
                lastColumn: last.column,
                startsAtEndpoint: first.day == selection.startDay,
                endsAtEndpoint: last.day == selection.endDay
            )
        }
    }

    private func dayButton(_ day: HistoryCalendarDay) -> some View {
        let isAvailable = availability.copiedDays.contains(day)
        let isInRange = previewSelection?.contains(day) == true
        let isEndpoint = previewSelection?.startDay == day || previewSelection?.endDay == day
        let isHovered = hoveredDay == day && isAvailable

        return ZStack {
            Button {
                guard isAvailable else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    draft.select(day)
                    hoveredDay = nil
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(isHovered && !isInRange ? 0.10 : 0))
                        .frame(
                            width: HistoryDatePickerLayout.selectionDiameter,
                            height: HistoryDatePickerLayout.selectionDiameter
                        )

                    if isEndpoint {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(
                                width: HistoryDatePickerLayout.selectionDiameter,
                                height: HistoryDatePickerLayout.selectionDiameter
                            )
                            .transition(.opacity)
                    }

                    Text(String(day.day))
                        .font(.system(size: 12, weight: isEndpoint ? .semibold : .regular))
                        .foregroundStyle(
                            dayForegroundStyle(
                                isAvailable: isAvailable,
                                isEndpoint: isEndpoint,
                                isInRange: isInRange
                            )
                        )

                    if focusedDay == day {
                        Circle()
                            .stroke(
                                isEndpoint
                                    ? Color.white.opacity(0.88)
                                    : Color.accentColor.opacity(0.82),
                                lineWidth: 1
                            )
                            .frame(
                                width: HistoryDatePickerLayout.selectionDiameter + 2,
                                height: HistoryDatePickerLayout.selectionDiameter + 2
                            )
                    }
                }
                .frame(
                    width: HistoryDatePickerLayout.dayHeight,
                    height: HistoryDatePickerLayout.dayHeight
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .focused($focusedDay, equals: day)
            .focusEffectDisabled()
            .clipShape(Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovered)
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            guard isHovering, isAvailable else { return }
            hoveredDay = day
        }
        .help(accessibilityDate(for: day))
        .accessibilityLabel(accessibilityDate(for: day))
        .accessibilityValue(accessibilityValue(for: day, isAvailable: isAvailable))
        .accessibilityHint(
            isAvailable
                ? String(localized: "Select as a date range endpoint")
                : String(localized: "No clipboard items on this day")
        )
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            HistoryDatePickerFooterButton(
                title: String(localized: "Cancel"),
                isProminent: false,
                isEnabled: true,
                action: onCancel
            )
            .keyboardShortcut(.cancelAction)
            HistoryDatePickerFooterButton(
                title: String(localized: "Apply"),
                isProminent: true,
                isEnabled: draft.selection != nil
            ) {
                guard let selection = draft.selection else { return }
                onApply(selection)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var monthTitle: String {
        guard let date = visibleMonth.firstDay.date(in: calendar) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? []
        guard symbols.count == 7 else { return symbols }
        let startIndex = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private func dayForegroundStyle(
        isAvailable: Bool,
        isEndpoint: Bool,
        isInRange: Bool
    ) -> AnyShapeStyle {
        if isEndpoint {
            return AnyShapeStyle(Color.white)
        }
        if isAvailable {
            return AnyShapeStyle(Color.primary)
        }
        if isInRange {
            return AnyShapeStyle(Color.primary.opacity(0.62))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.38))
    }

    private func accessibilityDate(for day: HistoryCalendarDay) -> String {
        guard let date = day.date(in: calendar) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func accessibilityValue(for day: HistoryCalendarDay, isAvailable: Bool) -> String {
        guard isAvailable else { return String(localized: "Unavailable") }
        guard let selection = previewSelection, selection.contains(day) else {
            return String(localized: "Available")
        }
        if selection.startDay == day, selection.endDay == day {
            return String(localized: "Selected")
        }
        if selection.startDay == day {
            return String(localized: "Range start")
        }
        if selection.endDay == day {
            return String(localized: "Range end")
        }
        return String(localized: "In selected range")
    }

    private func navigateMonth(by value: Int) {
        guard value < 0 ? canNavigateBackward : canNavigateForward,
            let nextMonth = visibleMonth.addingMonths(value, calendar: calendar)
        else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            visibleMonth = nextMonth
            hoveredDay = nil
        }
        focusedDay = nearestAvailableDay(in: nextMonth)
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let dayDelta: Int
        switch direction {
        case .left:
            dayDelta = -1
        case .right:
            dayDelta = 1
        case .up:
            dayDelta = -7
        case .down:
            dayDelta = 7
        default:
            return
        }
        guard let origin = focusedDay ?? draft.selection?.endDay ?? availability.latestDay,
            let nextDay = nextAvailableDay(from: origin, initialDelta: dayDelta)
        else { return }
        focusedDay = nextDay
        if let nextMonth = HistoryCalendarMonth(containing: nextDay, calendar: calendar),
            nextMonth.firstDay != visibleMonth.firstDay
        {
            visibleMonth = nextMonth
        }
    }

    private func nextAvailableDay(
        from origin: HistoryCalendarDay,
        initialDelta: Int
    ) -> HistoryCalendarDay? {
        guard let originDate = origin.date(in: calendar),
            let earliestDay = availability.earliestDay,
            let latestDay = availability.latestDay
        else { return nil }
        let direction = initialDelta < 0 ? -1 : 1
        var offset = initialDelta
        while let candidateDate = calendar.date(byAdding: .day, value: offset, to: originDate) {
            let candidate = HistoryCalendarDay(date: candidateDate, calendar: calendar)
            guard candidate >= earliestDay, candidate <= latestDay else { return nil }
            if availability.copiedDays.contains(candidate) {
                return candidate
            }
            offset += direction
        }
        return nil
    }

    private func nearestAvailableDay(in month: HistoryCalendarMonth) -> HistoryCalendarDay? {
        month.days.compactMap { $0 }.first(where: availability.copiedDays.contains)
    }
}

private struct HistoryDatePickerNavigationButton: View {
    let symbolName: String
    let accessibilityLabel: String
    let isEnabled: Bool
    let action: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(
            HistoryDatePickerNavigationButtonStyle(
                isEnabled: isEnabled,
                isHovering: isHovering,
                reduceMotion: reduceMotion
            )
        )
        .disabled(!isEnabled)
        .onHover { isHovering in
            guard isEnabled else { return }
            self.isHovering = isHovering
        }
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private struct HistoryDatePickerFooterButton: View {
    let title: String
    let isProminent: Bool
    let isEnabled: Bool
    let action: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foregroundColor: Color {
        isProminent ? .white : .primary
    }

    private var glassTint: Color? {
        isProminent ? Color.accentColor.opacity(0.82) : nil
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 14)
                .frame(minHeight: 30, maxHeight: 30)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .bufferGlassSurface(
            cornerRadius: 15,
            tint: glassTint,
            interactive: isEnabled
        )
        .opacity(isEnabled ? 1 : 0.42)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isEnabled
        )
    }
}

private enum HistoryDatePickerLayout {
    static let columnCount = 7
    static let rowCount = 6
    static let columnSpacing: CGFloat = 2
    static let rowSpacing: CGFloat = 2
    static let dayHeight: CGFloat = 32
    static let selectionDiameter: CGFloat = 27
    static let rangeHeight = selectionDiameter
    static let gridHeight =
        CGFloat(rowCount) * dayHeight
        + CGFloat(rowCount - 1) * rowSpacing
}

private struct HistoryDateRangeSegment: Identifiable {
    let row: Int
    let firstColumn: Int
    let lastColumn: Int
    let startsAtEndpoint: Bool
    let endsAtEndpoint: Bool

    var id: Int { row }
}

private struct HistoryDateRangeLayer: View {
    let segments: [HistoryDateRangeSegment]

    var body: some View {
        GeometryReader { proxy in
            let columnWidth =
                (proxy.size.width
                    - CGFloat(HistoryDatePickerLayout.columnCount - 1)
                    * HistoryDatePickerLayout.columnSpacing)
                / CGFloat(HistoryDatePickerLayout.columnCount)

            ForEach(segments) { segment in
                let columnStep = columnWidth + HistoryDatePickerLayout.columnSpacing
                let firstCellMinX =
                    CGFloat(segment.firstColumn)
                    * columnStep
                let lastCellMinX = CGFloat(segment.lastColumn) * columnStep
                let startX =
                    firstCellMinX
                    + (segment.startsAtEndpoint ? columnWidth / 2 : 0)
                let endX =
                    lastCellMinX
                    + (segment.endsAtEndpoint ? columnWidth / 2 : columnWidth)
                let width = max(0, endX - startX)
                let y =
                    CGFloat(segment.row)
                    * (HistoryDatePickerLayout.dayHeight + HistoryDatePickerLayout.rowSpacing)
                    + HistoryDatePickerLayout.dayHeight / 2

                if width > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor.opacity(0.19))
                        .frame(width: width, height: HistoryDatePickerLayout.rangeHeight)
                        .position(x: startX + width / 2, y: y)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HistoryDatePickerNavigationButtonStyle: ButtonStyle {
    let isEnabled: Bool
    let isHovering: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isEnabled
                    ? Color.primary
                    : Color.secondary.opacity(0.35)
            )
            .background(
                Color.primary.opacity(backgroundOpacity(isPressed: configuration.isPressed)),
                in: Circle()
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: isHovering
            )
    }

    private func backgroundOpacity(isPressed: Bool) -> Double {
        if !isEnabled {
            return 0
        }
        if isPressed {
            return 0.14
        }
        if isHovering {
            return 0.08
        }
        return 0
    }
}
