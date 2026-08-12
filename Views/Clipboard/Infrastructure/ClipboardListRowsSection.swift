import AppKit
import SwiftUI

struct ClipboardListRowsSection: View {
    let rows: [ClipboardListStructure.DisplayRow]
    let items: [ClipboardItem]
    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void

    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator

    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int

    var body: some View {
        ForEach(rows) { row in
            switch row.kind {
            case .header(let title, let systemImage):
                ClipboardSectionHeader(
                    title: title,
                    systemImage: systemImage
                )
                .padding(.leading, ClipboardListStructure.LayoutMetrics.contentPadding)

            case .divider:
                ClipboardSectionDivider()

            case .item(let item):
                itemRow(for: item)
            }
        }
    }

    private func itemRow(for item: ClipboardItem) -> some View {
        let index = indexForItem(item)
        let previousItemID = adjacentItemID(before: index)
        let nextItemID = adjacentItemID(after: index)

        return ClipboardInteractiveItemRow(
            item: item,
            index: index,
            store: store,
            settings: settings,
            primaryLabelText: primaryLabelText(item),
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: previousItemID.map { selectedIDs.contains($0) } ?? false,
            joinsSelectionBelow: nextItemID.map { selectedIDs.contains($0) } ?? false,
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: quickPasteBadgeNumberByItemID[item.id],
            isContextMenuHighlighted: contextMenuState.highlightedItemID == item.id,
            contextMenuIsActive: contextMenuState.highlightedItemID != nil,
            onCommitSelection: onCommitSelection,
            onSelectSingle: onSelectSingle,
            onToggleSelection: onToggleSelection,
            onExtendSelectionTo: onExtendSelectionTo,
            contextMenuActions: contextMenuActions(item.id),
            onPrimaryInteraction: contextMenuState.clear,
            onContextMenuAction: { itemID, action in
                contextMenuState.clear()
                onContextMenuAction(itemID, action)
            },
            onSecondaryClick: {
                contextMenuState.highlight(item.id)
            }
        )
        .id(clipboardListScrollID(for: item.id))
        .background {
            if measuredScrollCoordinator.pendingItemID == item.id {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ClipboardScrollTargetFramePreferenceKey.self,
                        value: proxy.frame(in: .named(ClipboardListCoordinateSpace.content))
                    )
                }
            }
        }
    }

    private func adjacentItemID(before index: Int) -> UUID? {
        let previousIndex = index - 1
        guard items.indices.contains(previousIndex) else {
            return nil
        }

        return items[previousIndex].id
    }

    private func adjacentItemID(after index: Int) -> UUID? {
        let nextIndex = index + 1
        guard items.indices.contains(nextIndex) else {
            return nil
        }

        return items[nextIndex].id
    }
}

private struct ClipboardInteractiveItemRow: View {
    let item: ClipboardItem
    let index: Int
    let store: ClipboardStore
    let settings: SettingsManager
    let primaryLabelText: String
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let isContextMenuHighlighted: Bool
    let contextMenuIsActive: Bool
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: [HistoryItemActionDescriptor]
    let onPrimaryInteraction: () -> Void
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onSecondaryClick: () -> Void

    @State private var isHovered = false

    var body: some View {
        ClipboardItemRow(
            item: item,
            store: store,
            settings: settings,
            primaryLabelText: primaryLabelText,
            isMultiSelected: isMultiSelected,
            joinsSelectionAbove: joinsSelectionAbove,
            joinsSelectionBelow: joinsSelectionBelow,
            selectionJoinOverlap: selectionJoinOverlap,
            quickPasteNumber: quickPasteNumber,
            isHovered: isHovered || isContextMenuHighlighted
        )
        .contentShape(Rectangle())
        .overlay {
            ClickModifierDetector(
                onClickWithModifiers: handlePrimaryMouseDown(modifiers:),
                onDoubleClick: handleDoubleClick,
                onHoverChanged: handleHoverChanged(_:),
                onSecondaryClick: onSecondaryClick
            )
        }
        .contextMenu {
            HistoryActionMenuContent(
                actions: contextMenuActions,
                onSelect: { action in
                    onContextMenuAction(item.id, action)
                }
            )
        }
    }

    private func handlePrimaryMouseDown(modifiers: NSEvent.ModifierFlags) {
        onPrimaryInteraction()

        if modifiers.hasCommand {
            onToggleSelection(item.id)
        } else if modifiers.hasShift {
            onExtendSelectionTo(item.id)
        } else {
            onSelectSingle(item.id, index)
        }
    }

    private func handleDoubleClick() {
        onPrimaryInteraction()
        onSelectSingle(item.id, index)
        onCommitSelection()
    }

    private func handleHoverChanged(_ hovering: Bool) {
        guard !contextMenuIsActive || !hovering else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHovered = hovering
        }
    }
}
