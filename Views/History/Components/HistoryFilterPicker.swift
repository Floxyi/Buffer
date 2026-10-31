import SwiftUI

enum HistoryFilterPickerOptionIcon: Sendable {
    case symbol(String)
    case application(ClipboardItem)
}

struct HistoryFilterPickerOption<ID: Hashable & Sendable>: Identifiable, Sendable {
    let id: ID
    let title: String
    let icon: HistoryFilterPickerOptionIcon
}

struct HistoryFilterPickerControl<ID: Hashable & Sendable>: View {
    let title: String
    let symbolName: String
    let selectedID: ID?
    let options: [HistoryFilterPickerOption<ID>]
    let selectedApplicationIconItem: ClipboardItem?
    let isEnabled: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityIdentifier: String
    let clearAccessibilityLabel: String
    let clearAccessibilityIdentifier: String
    let help: String
    let onSelect: @MainActor @Sendable (ID?) -> Void

    @State private var isPresented = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                isPresented.toggle()
            } label: {
                HistoryFilterControlLabel(
                    title: title,
                    symbolName: symbolName,
                    showsMenuChevron: true,
                    isExpanded: isPresented,
                    trailingAccessoryWidth: selectedID == nil ? 0 : 26,
                    applicationIconItem: selectedApplicationIconItem
                )
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled || options.isEmpty)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityIdentifier(accessibilityIdentifier)
            .background {
                HistoryAnchoredPopover(isPresented: $isPresented) {
                    HistoryFilterPickerPopover(
                        options: options,
                        selectedID: selectedID,
                        onCancel: { isPresented = false },
                        onSelect: { id in
                            onSelect(id)
                            isPresented = false
                        }
                    )
                }
            }

            if selectedID != nil {
                HistoryFilterClearButton(
                    accessibilityLabel: clearAccessibilityLabel,
                    accessibilityIdentifier: clearAccessibilityIdentifier
                ) {
                    onSelect(nil)
                }
            }
        }
        .historyFilterControlSurface(
            isActive: selectedID != nil,
            isExpanded: isPresented
        )
        .opacity(isEnabled && !options.isEmpty ? 1 : 0.45)
        .help(help)
    }
}

private struct HistoryFilterPickerPopover<ID: Hashable & Sendable>: View {
    let options: [HistoryFilterPickerOption<ID>]
    let selectedID: ID?
    let onCancel: @MainActor @Sendable () -> Void
    let onSelect: @MainActor @Sendable (ID) -> Void

    @FocusState private var focusedID: ID?

    private var contentHeight: CGFloat {
        let rowCount = CGFloat(options.count)
        let spacingCount = CGFloat(max(0, options.count - 1))
        let naturalHeight =
            rowCount * HistoryFilterPickerLayout.rowHeight
            + spacingCount * HistoryFilterPickerLayout.rowSpacing
            + HistoryFilterPickerLayout.contentInset * 2
        return min(naturalHeight, HistoryFilterPickerLayout.maximumContentHeight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: HistoryFilterPickerLayout.rowSpacing) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    HistoryFilterPickerRow(
                        option: option,
                        position: rowPosition(at: index),
                        isSelected: option.id == selectedID,
                        isFocused: option.id == focusedID
                    ) {
                        onSelect(option.id)
                    }
                    .focused($focusedID, equals: option.id)
                }
            }
            .frame(width: HistoryFilterPickerLayout.rowWidth)
            .padding(HistoryFilterPickerLayout.contentInset)
        }
        .scrollIndicators(options.count > 8 ? .automatic : .hidden)
        .frame(width: HistoryFilterPickerLayout.popoverWidth, height: contentHeight)
        .clipShape(
            RoundedRectangle(
                cornerRadius: HistoryFilterPickerLayout.popoverCornerRadius,
                style: .continuous
            )
        )
        .onAppear {
            focusedID = selectedID ?? options.first?.id
        }
        .onExitCommand(perform: onCancel)
        .onMoveCommand(perform: moveFocus(_:))
        .accessibilityElement(children: .contain)
    }

    private func rowPosition(at index: Int) -> HistoryFilterPickerRowPosition {
        if options.count == 1 {
            return .only
        }
        if index == options.startIndex {
            return .first
        }
        if index == options.index(before: options.endIndex) {
            return .last
        }
        return .middle
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down, !options.isEmpty else { return }
        let currentIndex = focusedID.flatMap { focusedID in
            options.firstIndex { $0.id == focusedID }
        }
        let nextIndex: Int
        switch direction {
        case .up:
            nextIndex = max(0, (currentIndex ?? options.count) - 1)
        case .down:
            nextIndex = min(options.count - 1, (currentIndex ?? -1) + 1)
        default:
            return
        }
        focusedID = options[nextIndex].id
    }
}

private enum HistoryFilterPickerLayout {
    static let popoverWidth: CGFloat = 224
    static let contentInset: CGFloat = 4
    static let rowWidth = popoverWidth - contentInset * 2
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 2
    static let maximumContentHeight: CGFloat = 280
    static let popoverCornerRadius: CGFloat = 22
    static let edgeRowCornerRadius = popoverCornerRadius - contentInset
    static let innerRowCornerRadius: CGFloat = 6
}

private enum HistoryFilterPickerRowPosition {
    case only
    case first
    case middle
    case last
}

private struct HistoryFilterPickerRow<ID: Hashable & Sendable>: View {
    let option: HistoryFilterPickerOption<ID>
    let position: HistoryFilterPickerRowPosition
    let isSelected: Bool
    let isFocused: Bool
    let action: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                optionIcon
                    .frame(width: 18, height: 18)
                Text(option.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(
                maxWidth: .infinity,
                minHeight: HistoryFilterPickerLayout.rowHeight,
                maxHeight: HistoryFilterPickerLayout.rowHeight
            )
            .background(rowBackground, in: rowShape)
            .overlay {
                if isFocused, !isSelected {
                    rowShape
                        .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                }
            }
            .contentShape(rowShape)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovering in
            self.isHovering = isHovering
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isFocused)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? String(localized: "Selected") : "")
    }

    @ViewBuilder
    private var optionIcon: some View {
        switch option.icon {
        case .symbol(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .medium))
        case .application(let item):
            ClipboardApplicationIconView(item: item, size: 16)
        }
    }

    private var rowShape: UnevenRoundedRectangle {
        let innerRadius = HistoryFilterPickerLayout.innerRowCornerRadius
        let outerRadius = HistoryFilterPickerLayout.edgeRowCornerRadius

        switch position {
        case .only:
            return UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        case .first:
            return UnevenRoundedRectangle(
                topLeadingRadius: outerRadius,
                bottomLeadingRadius: innerRadius,
                bottomTrailingRadius: innerRadius,
                topTrailingRadius: outerRadius,
                style: .continuous
            )
        case .middle:
            return UnevenRoundedRectangle(
                topLeadingRadius: innerRadius,
                bottomLeadingRadius: innerRadius,
                bottomTrailingRadius: innerRadius,
                topTrailingRadius: innerRadius,
                style: .continuous
            )
        case .last:
            return UnevenRoundedRectangle(
                topLeadingRadius: innerRadius,
                bottomLeadingRadius: outerRadius,
                bottomTrailingRadius: outerRadius,
                topTrailingRadius: innerRadius,
                style: .continuous
            )
        }
    }

    private var rowBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor)
        }
        if isFocused {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        if isHovering {
            return AnyShapeStyle(Color.primary.opacity(0.08))
        }
        return AnyShapeStyle(Color.clear)
    }
}
