import AppKit
import SwiftUI

struct HistorySearchBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var applicationIconLoader = ClipboardApplicationIconLoader.shared

    @Binding var searchText: String
    let filteredItemCount: Int
    @Binding var isSearchFocused: Bool
    let searchSelectionToken: Int
    let filterState: HistoryFilterState
    let applicationOptions: [HistoryApplicationFilterOption]
    let onSetBookmarkedOnly: @MainActor @Sendable (Bool) -> Void
    let onSelectApplication: @MainActor @Sendable (String?) -> Void
    let onSelectKind: @MainActor @Sendable (ClipboardItemKind?) -> Void
    let onSelectDatePreset: @MainActor @Sendable (HistoryDateFilterPreset) -> Void

    @State private var prefetchedApplicationIconToken: String?

    private var filterPresentation: HistoryFilterBarPresentation {
        HistoryFilterBarPresentation(
            filterState: filterState,
            hasApplicationOptions: !applicationOptions.isEmpty
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
                .disabled(searchText.isEmpty)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .center)

            Text("\(filteredItemCount) items")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(.secondary.opacity(0.72))
                .frame(width: 80, height: 24, alignment: .trailing)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 12)
        .frame(height: 52, alignment: .center)
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
        ZStack(alignment: .trailing) {
            Menu {
                Picker(
                    String(localized: "Application"),
                    selection: Binding(
                        get: { filterState.selectedApplication?.bundleIdentifier },
                        set: onSelectApplication
                    )
                ) {
                    ForEach(applicationOptions) { option in
                        HistoryApplicationMenuOptionLabel(
                            option: option,
                            appearance: applicationIconAppearance
                        )
                        .tag(Optional(option.bundleIdentifier))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HistoryFilterControlLabel(
                    title: filterPresentation.application.title,
                    symbolName: "circle.grid.3x3.fill",
                    showsMenuChevron: true,
                    trailingAccessoryWidth: filterPresentation.application.isActive ? 26 : 0,
                    applicationIconItem: filterState.selectedApplication?.iconItem
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .disabled(
                !filterPresentation.application.isEnabled
                    || prefetchedApplicationIconToken != applicationIconPrefetchToken
            )
            .accessibilityLabel(filterPresentation.application.accessibilityLabel)
            .accessibilityValue(filterPresentation.application.accessibilityValue)
            .accessibilityIdentifier(filterPresentation.application.accessibilityIdentifier)

            if filterPresentation.application.isActive {
                HistoryFilterClearButton(
                    accessibilityLabel: String(localized: "Clear Application Filter"),
                    accessibilityIdentifier: "historyFilter.app.clear"
                ) {
                    onSelectApplication(nil)
                }
            }
        }
        .historyFilterControlSurface(isActive: filterPresentation.application.isActive)
        .opacity(filterPresentation.application.isEnabled ? 1 : 0.45)
        .help(String(localized: "Filter by source application"))
    }

    private var kindControl: some View {
        ZStack(alignment: .trailing) {
            Menu {
                Picker(
                    String(localized: "Type"),
                    selection: Binding(
                        get: { filterState.selectedKind },
                        set: onSelectKind
                    )
                ) {
                    ForEach(ClipboardItemKind.allCases, id: \.self) { kind in
                        let definition = ClipboardItemPresentation.definition(for: kind)
                        Label(definition.displayName, systemImage: definition.symbolName)
                            .tag(Optional(kind))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                let definition = filterState.selectedKind.map(ClipboardItemPresentation.definition(for:))
                HistoryFilterControlLabel(
                    title: filterPresentation.kind.title,
                    symbolName: definition?.symbolName ?? "square.stack.3d.up",
                    showsMenuChevron: true,
                    trailingAccessoryWidth: filterPresentation.kind.isActive ? 26 : 0
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(filterPresentation.kind.accessibilityLabel)
            .accessibilityValue(filterPresentation.kind.accessibilityValue)
            .accessibilityIdentifier(filterPresentation.kind.accessibilityIdentifier)

            if filterPresentation.kind.isActive {
                HistoryFilterClearButton(
                    accessibilityLabel: String(localized: "Clear Item Type Filter"),
                    accessibilityIdentifier: "historyFilter.type.clear"
                ) {
                    onSelectKind(nil)
                }
            }
        }
        .historyFilterControlSurface(isActive: filterPresentation.kind.isActive)
        .help(String(localized: "Filter by item type"))
    }

    private var dateControl: some View {
        ZStack(alignment: .trailing) {
            Menu {
                Picker(
                    String(localized: "Date"),
                    selection: Binding(
                        get: { filterState.datePreset },
                        set: onSelectDatePreset
                    )
                ) {
                    ForEach(HistoryDateFilterPreset.selectableCases) { preset in
                        Label(preset.displayName, systemImage: "calendar")
                            .tag(preset)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HistoryFilterControlLabel(
                    title: filterPresentation.date.title,
                    symbolName: "calendar",
                    showsMenuChevron: true,
                    trailingAccessoryWidth: filterPresentation.date.isActive ? 26 : 0
                )
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(filterPresentation.date.accessibilityLabel)
            .accessibilityValue(filterPresentation.date.accessibilityValue)
            .accessibilityIdentifier(filterPresentation.date.accessibilityIdentifier)

            if filterPresentation.date.isActive {
                HistoryFilterClearButton(
                    accessibilityLabel: String(localized: "Clear Date Filter"),
                    accessibilityIdentifier: "historyFilter.date.clear"
                ) {
                    onSelectDatePreset(.allDates)
                }
            }
        }
        .historyFilterControlSurface(isActive: filterPresentation.date.isActive)
        .help(String(localized: "Filter by copied date"))
    }
}

private struct HistoryApplicationMenuOptionLabel: View {
    let option: HistoryApplicationFilterOption
    let appearance: ClipboardApplicationIconAppearance

    var body: some View {
        Label {
            Text(option.displayName)
        } icon: {
            if let icon = ClipboardApplicationIconLoader.shared.cachedIcon(
                for: option.iconItem,
                appearance: appearance
            ) {
                Image(
                    nsImage: ClipboardApplicationIconLoader.logicalSizeCopy(
                        of: icon,
                        size: 16
                    )
                )
            } else {
                Image(systemName: "app.fill")
            }
        }
    }
}

private struct HistoryFilterControlLabel: View {
    let title: String
    let symbolName: String
    let showsMenuChevron: Bool
    var trailingAccessoryWidth: CGFloat = 0
    var applicationIconItem: ClipboardItem?

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
    }
}

private struct HistoryFilterClearButton: View {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .padding(.trailing, 2)
    }
}

extension View {
    fileprivate func historyFilterControlSurface(isActive: Bool) -> some View {
        self
            .foregroundStyle(isActive ? Color.accentColor : Color.primary.opacity(0.82))
            .background(
                isActive ? Color.accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
            .bufferGlassSurface(
                cornerRadius: 14,
                tint: isActive ? Color.accentColor.opacity(0.12) : nil,
                interactive: true
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

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        if context.coordinator.pendingSelectionToken != selectionToken {
            context.coordinator.pendingSelectionToken = selectionToken
        }

        if isFocused {
            DispatchQueue.main.async {
                guard let window = nsView.window else { return }

                if window.firstResponder !== nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                }

                context.coordinator.applyPendingSelectionIfNeeded(to: nsView)
            }
        }
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

            textField.selectText(nil)
            editor.selectedRange = NSRange(location: 0, length: editor.string.count)
            appliedSelectionToken = pendingSelectionToken
        }
    }
}

private final class FocusableSearchTextField: NSTextField {
    var focusChangeHandler: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
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
