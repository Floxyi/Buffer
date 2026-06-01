import SwiftUI

struct ClipboardListRowsSection: View {
    let rows: [ClipboardListStructure.DisplayRow]
    let items: [ClipboardItem]
    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let hoveredItemID: UUID?
    let sourceIconRefreshToken: Int
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onHoveredItemIDChanged: (UUID?) -> Void
    let onSelectedIndexChanged: (Int) -> Void

    @ObservedObject var scrollController: ScrollController
    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator

    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int

    private var highlightedItemID: UUID? {
        contextMenuState.displayedHighlightedItemID(hoveredItemID: hoveredItemID)
    }

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

        return ClipboardItemRow(
            item: item,
            store: store,
            settings: settings,
            primaryLabelText: primaryLabelText(item),
            scrollActivityTracker: scrollController.activityTracker,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: previousItemID.map { selectedIDs.contains($0) } ?? false,
            joinsSelectionBelow: nextItemID.map { selectedIDs.contains($0) } ?? false,
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: quickPasteBadgeNumberByItemID[item.id],
            isHovered: highlightedItemID == item.id,
            sourceIconRefreshToken: sourceIconRefreshToken
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
        .contentShape(Rectangle())
        .overlay(
            ClickModifierDetector { modifiers in
                contextMenuState.clear()
                onSelectedIndexChanged(index)

                if modifiers.hasCommand {
                    onToggleSelection(item.id)
                } else if modifiers.hasShift {
                    onExtendSelectionTo(item.id)
                } else {
                    onSelectSingle(item.id)
                }
            } onHoverChanged: { hovering in
                guard !scrollController.activityTracker.isScrolling else { return }
                guard contextMenuState.highlightedItemID == nil || !hovering else { return }

                onHoveredItemIDChanged(
                    hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                )
            } onSecondaryClick: {
                onHoveredItemIDChanged(nil)
                contextMenuState.highlight(item.id)
            },
            alignment: .center
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    // Handled by ClickModifierDetector.
                }
        )
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    onSelectedIndexChanged(index)
                    onSelectSingle(item.id)
                    onCommitSelection()
                }
        )
        .contextMenu {
            HistoryActionMenuContent(
                actions: contextMenuActions(item.id),
                onSelect: { action in
                    contextMenuState.clear()
                    onSelectedIndexChanged(index)
                    onContextMenuAction(item.id, action)
                }
            )
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
