import AppKit
import SwiftUI

enum HistorySearchActivityPhase: Equatable, Sendable {
    case idle
    case updating
    case searching
}

protocol HistorySearchActivityClock: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousHistorySearchActivityClock: HistorySearchActivityClock {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

struct HistorySearchActivityStateMachine: Sendable {
    let clock: any HistorySearchActivityClock

    init(clock: any HistorySearchActivityClock = ContinuousHistorySearchActivityClock()) {
        self.clock = clock
    }

    func run(
        isSearching: Bool,
        publish: @escaping @MainActor @Sendable (HistorySearchActivityPhase) -> Void
    ) async {
        await publish(.idle)
        guard isSearching else { return }
        do {
            try await clock.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
            await publish(.updating)
            try await clock.sleep(for: .milliseconds(800))
            try Task.checkCancellation()
            await publish(.searching)
        } catch {
            return
        }
    }
}

private struct HistorySearchActivityID: Hashable {
    let isSearching: Bool
    let query: String
}

struct HistorySearchBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var applicationIconLoader = ClipboardApplicationIconLoader.shared

    @Binding var searchText: String
    let filteredItemCount: Int
    let isSearching: Bool
    let searchStatus: ClipboardSearchStatus
    @Binding var isSearchFocused: Bool
    let searchSelectionToken: Int
    let filterState: HistoryFilterState
    let applicationOptions: [HistoryApplicationFilterOption]
    let dateAvailability: HistoryDateAvailability
    let filterCalendar: Calendar
    let onSetBookmarkedOnly: @MainActor @Sendable (Bool) -> Void
    let onSelectApplication: @MainActor @Sendable (String?) -> Void
    let onSelectKind: @MainActor @Sendable (ClipboardItemKind?) -> Void
    let onSelectDate: @MainActor @Sendable (HistoryDateFilterSelection?) -> Void

    @State private var prefetchedApplicationIconToken: String?
    @State private var searchActivityPhase = HistorySearchActivityPhase.idle
    private let searchActivityStateMachine = HistorySearchActivityStateMachine()

    private var filterPresentation: HistoryFilterBarPresentation {
        HistoryFilterBarPresentation(
            filterState: filterState,
            hasApplicationOptions: !applicationOptions.isEmpty,
            calendar: filterCalendar
        )
    }

    private var applicationIconAppearance: ClipboardApplicationIconAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var applicationIconPrefetchToken: String {
        let optionToken = applicationOptions.map {
            "\($0.bundleIdentifier):\($0.iconItem.id.uuidString)"
        }.joined(separator: "|")
        return "\(applicationIconAppearance.rawValue)|\(applicationIconLoader.iconRevision)|\(optionToken)"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            BufferPanelSeparator()
            filterRow
        }
        .background {
            HistoryPanelSurfaceBackground()
        }
        .task(id: applicationIconPrefetchToken) {
            guard !applicationOptions.isEmpty else {
                prefetchedApplicationIconToken = applicationIconPrefetchToken
                return
            }
            prefetchedApplicationIconToken = nil
            await applicationIconLoader.prewarmIcons(
                for: applicationOptions.map(\.iconItem),
                appearance: applicationIconAppearance,
                limit: 120
            )
            guard !Task.isCancelled else { return }
            prefetchedApplicationIconToken = applicationIconPrefetchToken
        }
        .task(id: HistorySearchActivityID(isSearching: isSearching, query: searchText)) {
            await searchActivityStateMachine.run(isSearching: isSearching) { phase in
                searchActivityPhase = phase
            }
        }
    }

    private var searchRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary.opacity(0.82))
                .font(.system(size: 18, weight: .medium))
                .frame(width: 18, height: 24)
                .padding(.leading, 2)

            HStack(alignment: .center, spacing: 10) {
                SearchFieldBridge(
                    text: $searchText,
                    isFocused: $isSearchFocused,
                    selectionToken: searchSelectionToken,
                    placeholder: "Search clipboard..."
                )
                .frame(height: 24, alignment: .center)

                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.7))
                        .font(.system(size: 14))
                        .frame(width: 16, height: 24)
                }
                .buttonStyle(.plain)
                .opacity(searchText.isEmpty ? 0 : 1)
                .scaleEffect(searchText.isEmpty ? 0.86 : 1)
                .animation(.easeOut(duration: 0.14), value: searchText.isEmpty)
                .disabled(searchText.isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .center)

            HStack(spacing: 5) {
                if isSearching, searchActivityPhase == .searching {
                    ProgressView()
                        .controlSize(.mini)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Text(searchStatusText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.72))
                    .contentTransition(.opacity)
            }
            .animation(.easeOut(duration: 0.16), value: searchActivityPhase)
            .frame(width: 80, height: 24, alignment: .trailing)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .frame(height: 52, alignment: .center)
    }

    private var searchStatusText: String {
        if isSearching {
            switch searchActivityPhase {
            case .idle:
                return "\(filteredItemCount) items"
            case .updating:
                return String(localized: "Updating…")
            case .searching:
                return String(localized: "Searching…")
            }
        }
        if case .degraded = searchStatus.phase {
            return String(localized: "Search paused")
        }
        if case .recovering = searchStatus.phase {
            return String(localized: "Rebuilding…")
        }
        if !searchStatus.isReady, searchStatus.totalItemCount > 0 {
            return "\(searchStatus.indexedItemCount)/\(searchStatus.totalItemCount)"
        }
        return "\(filteredItemCount) items"
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            bookmarkControl
                .frame(maxWidth: .infinity)
            applicationControl
                .frame(maxWidth: .infinity)
            kindControl
                .frame(maxWidth: .infinity)
            dateControl
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bookmarkControl: some View {
        Button {
            onSetBookmarkedOnly(!filterState.isBookmarkedOnly)
        } label: {
            HistoryFilterControlLabel(
                title: filterPresentation.bookmarks.title,
                symbolName: filterState.isBookmarkedOnly ? "bookmark.fill" : "bookmark",
                showsMenuChevron: false
            )
        }
        .buttonStyle(.plain)
        .historyFilterControlSurface(isActive: filterPresentation.bookmarks.isActive)
        .accessibilityLabel(filterPresentation.bookmarks.accessibilityLabel)
        .accessibilityValue(filterPresentation.bookmarks.accessibilityValue)
        .accessibilityIdentifier(filterPresentation.bookmarks.accessibilityIdentifier)
        .help(String(localized: "Show bookmarked items only"))
    }

    private var applicationControl: some View {
        HistoryFilterPickerControl(
            title: filterPresentation.application.title,
            symbolName: "circle.grid.3x3.fill",
            selectedID: filterState.selectedApplication?.bundleIdentifier,
            options: applicationOptions.map {
                HistoryFilterPickerOption(
                    id: $0.bundleIdentifier,
                    title: $0.displayName,
                    icon: .application($0.iconItem)
                )
            },
            selectedApplicationIconItem: filterState.selectedApplication?.iconItem,
            isEnabled: filterPresentation.application.isEnabled
                && prefetchedApplicationIconToken == applicationIconPrefetchToken,
            accessibilityLabel: filterPresentation.application.accessibilityLabel,
            accessibilityValue: filterPresentation.application.accessibilityValue,
            accessibilityIdentifier: filterPresentation.application.accessibilityIdentifier,
            clearAccessibilityLabel: String(localized: "Clear Application Filter"),
            clearAccessibilityIdentifier: "historyFilter.app.clear",
            help: String(localized: "Filter by source application"),
            onSelect: onSelectApplication
        )
    }

    private var kindControl: some View {
        let selectedDefinition = filterState.selectedKind.map(
            ClipboardItemPresentation.definition(for:)
        )
        return HistoryFilterPickerControl(
            title: filterPresentation.kind.title,
            symbolName: selectedDefinition?.symbolName ?? "square.stack.3d.up",
            selectedID: filterState.selectedKind,
            options: ClipboardItemKind.allCases.map { kind in
                let definition = ClipboardItemPresentation.definition(for: kind)
                return HistoryFilterPickerOption(
                    id: kind,
                    title: definition.displayName,
                    icon: .symbol(definition.symbolName)
                )
            },
            selectedApplicationIconItem: nil,
            isEnabled: true,
            accessibilityLabel: filterPresentation.kind.accessibilityLabel,
            accessibilityValue: filterPresentation.kind.accessibilityValue,
            accessibilityIdentifier: filterPresentation.kind.accessibilityIdentifier,
            clearAccessibilityLabel: String(localized: "Clear Item Type Filter"),
            clearAccessibilityIdentifier: "historyFilter.type.clear",
            help: String(localized: "Filter by item type"),
            onSelect: onSelectKind
        )
    }

    private var dateControl: some View {
        HistoryDateFilterControl(
            title: filterPresentation.date.title,
            selection: filterState.dateSelection,
            availability: dateAvailability,
            calendar: filterCalendar,
            accessibilityLabel: filterPresentation.date.accessibilityLabel,
            accessibilityValue: filterPresentation.date.accessibilityValue,
            accessibilityIdentifier: filterPresentation.date.accessibilityIdentifier,
            onApply: onSelectDate
        )
    }
}

struct HistoryFilterControlLabel: View {
    let title: String
    let symbolName: String
    let showsMenuChevron: Bool
    var isExpanded = false
    var trailingAccessoryWidth: CGFloat = 0
    var applicationIconItem: ClipboardItem?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            controlIcon
            controlTitle
            Spacer(minLength: showsMenuChevron ? 2 : 0)
            if showsMenuChevron {
                menuChevron
            }
        }
        .padding(.horizontal, 10)
        .padding(.trailing, trailingAccessoryWidth)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var controlIcon: some View {
        if let applicationIconItem {
            ClipboardApplicationIconView(item: applicationIconItem, size: 14)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
        }
    }

    private var controlTitle: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var menuChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.16),
                value: isExpanded
            )
    }
}

struct HistoryFilterClearButton: View {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 24, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .padding(.trailing, 2)
    }
}

extension View {
    func historyFilterControlSurface(isActive: Bool) -> some View {
        modifier(
            HistoryFilterControlSurfaceModifier(isActive: isActive)
        )
    }
}

private struct HistoryFilterControlSurfaceModifier: ViewModifier {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foregroundColor: Color {
        isActive ? .accentColor : .primary.opacity(0.82)
    }

    private var overlayOpacity: Double {
        isActive ? 0.07 : 0
    }

    private var strokeOpacity: Double {
        isActive ? 0.12 : 0
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .foregroundStyle(foregroundColor)
            .background(Color.accentColor.opacity(overlayOpacity), in: shape)
            .overlay {
                shape.stroke(Color.accentColor.opacity(strokeOpacity), lineWidth: 0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .bufferGlassSurface(
                cornerRadius: 14,
                tint: isActive ? Color.accentColor.opacity(0.05) : nil,
                interactive: false
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.16),
                value: isActive
            )
    }
}

private struct SearchFieldBridge: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let selectionToken: Int
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> FocusableSearchTextField {
        let textField = FocusableSearchTextField(frame: .zero)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: 18)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.focusChangeHandler = { isFocused in
            context.coordinator.handleFocusChange(isFocused)
        }
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ nsView: FocusableSearchTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused

        let hasMarkedText = (nsView.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        if !hasMarkedText, nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if context.coordinator.pendingSelectionToken != selectionToken {
            context.coordinator.pendingSelectionToken = selectionToken
        }

        if isFocused {
            // Avoid AppKit choosing the field editor while the window is still
            // completing its initial layout. The focus controller enables the
            // field once the window is ready, yielding one stable TextInputUI
            // session instead of an automatic session followed by ours.
            nsView.allowsFocus = true
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }
                prepareSearchFieldEditor(in: window, for: nsView)

                if window.firstResponder !== nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                }

                context.coordinator.applyPendingSelectionIfNeeded(to: nsView)
            }
        }
    }

    private func prepareSearchFieldEditor(
        in window: NSWindow,
        for textField: NSTextField
    ) {
        guard let editor = window.fieldEditor(true, for: textField) as? NSTextView else { return }
        editor.configureForHistorySearch()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        var pendingSelectionToken = 0
        private var appliedSelectionToken = -1

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            // Keep IME composition local to AppKit. Publishing marked text would
            // launch SQLite work for transient phonetic input and render stale
            // highlights before the user commits the composition.
            if let editor = textField.currentEditor() as? NSTextView,
                editor.hasMarkedText()
            {
                return
            }
            if text.wrappedValue != textField.stringValue {
                text.wrappedValue = textField.stringValue
            }
        }

        func handleFocusChange(_ isFocused: Bool) {
            self.isFocused.wrappedValue = isFocused
        }

        func applyPendingSelectionIfNeeded(to textField: NSTextField) {
            guard pendingSelectionToken != appliedSelectionToken else { return }
            guard let editor = textField.currentEditor() else { return }

            editor.selectedRange = NSRange(location: 0, length: editor.string.count)
            appliedSelectionToken = pendingSelectionToken
        }
    }
}

private final class FocusableSearchTextField: NSTextField {
    var focusChangeHandler: ((Bool) -> Void)?
    var allowsFocus = false

    override var acceptsFirstResponder: Bool {
        allowsFocus && super.acceptsFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        guard allowsFocus else { return false }
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            focusChangeHandler?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            focusChangeHandler?(false)
        }
        return didResignFirstResponder
    }
}

extension NSTextView {
    fileprivate func configureForHistorySearch() {
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticTextReplacementEnabled = false
        inlinePredictionType = .no

        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none
        }
    }
}
