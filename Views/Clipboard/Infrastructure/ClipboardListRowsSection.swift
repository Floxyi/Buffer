import AppKit
import SwiftUI

/// Owns the single transient hover for the list without publishing view-model state.
@MainActor
final class ClipboardListHoverCoordinator {
    private var activeItemID: UUID?
    private var clearActiveHover: (() -> Void)?
    private var suppressesHoverUntilPointerMoves = false

    @discardableResult
    func activate(itemID: UUID, onClear: @escaping () -> Void) -> Bool {
        guard !suppressesHoverUntilPointerMoves else { return false }

        if activeItemID != itemID {
            clearCurrentHover()
        }

        activeItemID = itemID
        clearActiveHover = onClear
        return true
    }

    @discardableResult
    func activateFromPointerMovement(itemID: UUID, onClear: @escaping () -> Void) -> Bool {
        suppressesHoverUntilPointerMoves = false
        return activate(itemID: itemID, onClear: onClear)
    }

    func deactivate(itemID: UUID) {
        guard activeItemID == itemID else { return }
        activeItemID = nil
        clearActiveHover = nil
    }

    func suppressUntilPointerMoves() {
        suppressesHoverUntilPointerMoves = true
        clearCurrentHover()
    }

    func reset() {
        suppressesHoverUntilPointerMoves = false
        clearCurrentHover()
    }

    private func clearCurrentHover() {
        let clear = clearActiveHover
        activeItemID = nil
        clearActiveHover = nil
        clear?()
    }
}

struct ClipboardListRowsSection: View {
    #if DEBUG
        @Environment(\.clipboardListViewportProbe) private var viewportProbe
    #endif

    let rows: [ClipboardListStructure.DisplayRow]
    let renderingWindow: ClipboardListRenderingWindow
    let items: [ClipboardItem]
    let pinnedItemIDs: [UUID]
    let websitePreviewsEnabled: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let searchResultsByItemID: [UUID: ClipboardSearchHit]
    let queryText: String
    let committedQueryText: String
    let searchResultAnimationPolicy: SearchResultAnimationPolicy
    let allowsPinnedReordering: Bool
    let reduceMotion: Bool
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onReorderPinnedItems: (ClipboardPinnedReorderRequest) async -> Bool

    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var pinnedReorderCoordinator: ClipboardPinnedReorderCoordinator
    let scrollController: ScrollController
    let hoverCoordinator: ClipboardListHoverCoordinator

    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int
    let itemForID: (UUID) -> ClipboardItem?

    @ViewBuilder
    var body: some View {
        let highlightPlan = queryText.isEmpty ? nil : ClipboardQueryPlan(queryText)
        VStack(spacing: 0) {
            if renderingWindow.leadingSpacerHeight > 0 {
                Color.clear.frame(height: renderingWindow.leadingSpacerHeight)
            }
            VStack(spacing: ClipboardListStructure.LayoutMetrics.rowSpacing) {
                if allowsPinnedReordering, !pinnedItemIDs.isEmpty {
                    reorderableRows(highlightPlan: highlightPlan)
                } else {
                    standardRows(highlightPlan: highlightPlan)
                }
            }
            if renderingWindow.trailingSpacerHeight > 0 {
                Color.clear.frame(height: renderingWindow.trailingSpacerHeight)
            }
        }
    }

    private var displayedPinnedItemIDs: [UUID] {
        let transientIDs = pinnedReorderCoordinator.displayedItemIDs
        return transientIDs.isEmpty ? pinnedItemIDs : transientIDs
    }

    private var pinnedDragItems: [ClipboardPinnedDragItem] {
        displayedPinnedItemIDs.enumerated().map { index, itemID in
            ClipboardPinnedDragItem(id: itemID, visualIndex: index)
        }
    }

    private var usesPinnedDragInteraction: Bool {
        allowsPinnedReordering && pinnedItemIDs.count > 1
    }

    private var canReorderPinnedItems: Bool {
        usesPinnedDragInteraction && !pinnedReorderCoordinator.isCommitInFlight
    }

    private var renderedRows: ArraySlice<ClipboardListStructure.DisplayRow> {
        let lowerBound = renderingWindow.range.lowerBound.clamped(to: 0...rows.count)
        let upperBound = renderingWindow.range.upperBound.clamped(to: lowerBound...rows.count)
        return rows[lowerBound..<upperBound]
    }

    private func standardRows(highlightPlan: ClipboardQueryPlan?) -> some View {
        displayRows(renderedRows, highlightPlan: highlightPlan)
    }

    @ViewBuilder
    private func reorderableRows(highlightPlan: ClipboardQueryPlan?) -> some View {
        let pinnedBlockEnd = min(rows.count, pinnedItemIDs.count + 1)
        if renderingWindow.range.lowerBound < pinnedBlockEnd {
            pinnedHeader
            ForEach(pinnedDragItems) { dragItem in
                pinnedItemRow(for: dragItem, highlightPlan: highlightPlan)
            }
            let remainderStart = max(pinnedBlockEnd, renderingWindow.range.lowerBound)
            let remainderEnd = min(rows.count, renderingWindow.range.upperBound)
            if remainderStart < remainderEnd {
                displayRows(rows[remainderStart..<remainderEnd], highlightPlan: highlightPlan)
            }
        } else {
            displayRows(renderedRows, highlightPlan: highlightPlan)
        }
    }

    private func pinnedRowInteraction(
        for dragItem: ClipboardPinnedDragItem
    ) -> ClipboardPinnedRowInteraction {
        ClipboardPinnedRowInteraction(
            itemID: dragItem.id,
            nextItemID: displayedPinnedItemIDs[safe: dragItem.visualIndex + 1],
            onBeginDrag: {
                !dragPayload(startingAt: dragItem.id).isEmpty
            },
            canAcceptDrop: {
                pinnedReorderCoordinator.hasActiveDrag
            },
            onPreviewDrop: { destination in
                pinnedReorderCoordinator.preview(destination: destination)
            },
            onPerformDrop: { destination in
                pinnedReorderCoordinator.acceptDrop(
                    destination: destination,
                    animation: reduceMotion ? nil : .easeInOut(duration: 0.16),
                    commit: onReorderPinnedItems
                )
            },
            onDragLocationChanged: { pointerY, onAutoscrollFrame in
                pinnedReorderCoordinator.updateAutoscroll(
                    pointerY: pointerY,
                    scrollOffset: scrollController.scrollOffset,
                    viewportHeight: scrollController.viewportHeight,
                    scrollBy: scrollController.scrollBy(deltaY:),
                    onAutoscrollFrame: onAutoscrollFrame
                )
            },
            onDragEnded: {
                pinnedReorderCoordinator.dragSessionEnded()
            },
            onPrimaryMouseDown: { modifiers in
                selectUnselectedPinnedItemOnMouseDown(
                    dragItem.id,
                    modifiers: modifiers
                )
            },
            onClickWithModifiers: { modifiers in
                selectPinnedItem(dragItem.id, modifiers: modifiers)
            },
            onDoubleClick: {
                commitPinnedItem(dragItem.id)
            },
            onSecondaryClick: {
                contextMenuState.highlight(dragItem.id)
            },
            contextMenuActions: contextMenuActions(dragItem.id),
            onContextMenuAction: { action in
                contextMenuState.clear()
                onContextMenuAction(dragItem.id, action)
            },
            onContextMenuDismissed: {
                contextMenuState.clear()
            }
        )
    }

    private var pinnedHeader: some View {
        ClipboardSectionHeader(
            title: String(localized: "PINNED"),
            systemImage: nil
        )
        .padding(.leading, ClipboardListStructure.LayoutMetrics.contentPadding)
    }

    @ViewBuilder
    private func displayRows<Data: RandomAccessCollection>(
        _ displayRows: Data,
        highlightPlan: ClipboardQueryPlan?
    ) -> some View where Data.Element == ClipboardListStructure.DisplayRow {
        ForEach(displayRows) { row in
            switch row.kind {
            case .header(let title, let systemImage):
                ClipboardSectionHeader(title: title, systemImage: systemImage)
                    .padding(.leading, ClipboardListStructure.LayoutMetrics.contentPadding)
            case .divider:
                ClipboardSectionDivider()
            case .item(let item):
                itemRow(for: item, highlightPlan: highlightPlan)
            }
        }
    }

    @ViewBuilder
    private func pinnedItemRow(
        for dragItem: ClipboardPinnedDragItem,
        highlightPlan: ClipboardQueryPlan?
    ) -> some View {
        let itemID = dragItem.id
        if let item = itemForID(itemID) {
            itemRow(
                for: item,
                highlightPlan: highlightPlan,
                pinnedInteraction: usesPinnedDragInteraction
                    ? pinnedRowInteraction(for: dragItem) : nil,
                visualAdjacentItemIDs: (
                    displayedPinnedItemIDs[safe: dragItem.visualIndex - 1],
                    displayedPinnedItemIDs[safe: dragItem.visualIndex + 1]
                )
            )
            .accessibilityRepresentation {
                Button(primaryLabelText(item)) {
                    onSelectSingle(itemID, indexForItem(item))
                }
                .accessibilityValue(
                    item.isBookmarked
                        ? String(localized: "Pinned, Bookmarked")
                        : String(localized: "Pinned")
                )
                .accessibilityAction(named: Text("Move Up")) {
                    performAccessibilityMove(.up, itemID: itemID)
                }
                .accessibilityAction(named: Text("Move Down")) {
                    performAccessibilityMove(.down, itemID: itemID)
                }
            }
        }
    }

    private func dragPayload(startingAt itemID: UUID) -> [ClipboardPinnedDragItem] {
        guard canReorderPinnedItems else { return [] }
        let payload = pinnedReorderCoordinator.beginDrag(
            itemID: itemID,
            selectedItemIDs: selectedIDs
        )
        if !selectedIDs.contains(itemID), let item = itemForID(itemID) {
            onSelectSingle(itemID, indexForItem(item))
        }
        return payload
    }

    private func selectUnselectedPinnedItemOnMouseDown(
        _ itemID: UUID,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard !modifiers.hasCommand,
            !modifiers.hasShift,
            !selectedIDs.contains(itemID),
            let item = itemForID(itemID)
        else { return false }

        contextMenuState.clear()
        onSelectSingle(itemID, indexForItem(item))
        return true
    }

    private func selectPinnedItem(_ itemID: UUID, modifiers: NSEvent.ModifierFlags) {
        guard let item = itemForID(itemID) else { return }
        contextMenuState.clear()
        if modifiers.hasCommand {
            onToggleSelection(itemID)
        } else if modifiers.hasShift {
            onExtendSelectionTo(itemID)
        } else {
            onSelectSingle(itemID, indexForItem(item))
        }
    }

    private func commitPinnedItem(_ itemID: UUID) {
        guard let item = itemForID(itemID) else { return }
        contextMenuState.clear()
        onSelectSingle(itemID, indexForItem(item))
        onCommitSelection()
    }

    private func performAccessibilityMove(
        _ direction: ClipboardPinnedAccessibilityMove,
        itemID: UUID
    ) {
        guard canReorderPinnedItems,
            let request = pinnedReorderCoordinator.accessibilityRequest(
                for: itemID,
                direction: direction,
                selectedItemIDs: selectedIDs
            )
        else { return }
        pinnedReorderCoordinator.commitAccessibilityMove(
            request,
            animation: reduceMotion ? nil : .easeInOut(duration: 0.16),
            commit: onReorderPinnedItems
        )
    }

    private func itemRow(
        for item: ClipboardItem,
        highlightPlan: ClipboardQueryPlan?,
        pinnedInteraction: ClipboardPinnedRowInteraction? = nil,
        visualAdjacentItemIDs: (previous: UUID?, next: UUID?)? = nil
    ) -> some View {
        let index = indexForItem(item)
        let previousItemID: UUID?
        let nextItemID: UUID?
        if let visualAdjacentItemIDs {
            previousItemID = visualAdjacentItemIDs.previous
            nextItemID = visualAdjacentItemIDs.next
        } else {
            previousItemID = adjacentItemID(before: index)
            nextItemID = adjacentItemID(after: index)
        }
        let searchResult = searchResultsByItemID[item.id]
        let usesCommittedEvidence = queryText == committedQueryText
        let evidence = usesCommittedEvidence ? searchResult?.evidence : nil
        let searchSnippet = usesCommittedEvidence ? searchResult?.snippet : nil
        let displayedText: String
        if evidence?.field == .sourceApplication {
            displayedText = item.sourceAppDisplayName ?? primaryLabelText(item)
        } else {
            displayedText = searchSnippet?.text ?? primaryLabelText(item)
        }

        let row = ClipboardInteractiveItemRow(
            item: item,
            index: index,
            websitePreviewsEnabled: websitePreviewsEnabled,
            assetProvider: assetProvider,
            primaryLabelText: displayedText,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: previousItemID.map { selectedIDs.contains($0) } ?? false,
            joinsSelectionBelow: nextItemID.map { selectedIDs.contains($0) } ?? false,
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: quickPasteBadgeNumberByItemID[item.id],
            queryPlan: highlightPlan,
            contentMatchClassification: evidence?.kind.classification ?? .exact,
            matchEvidence: evidence,
            searchSnippet: searchSnippet,
            isContextMenuHighlighted: contextMenuState.highlightedItemID == item.id,
            contextMenuIsActive: contextMenuState.highlightedItemID != nil,
            pinnedInteraction: pinnedInteraction,
            onCommitSelection: onCommitSelection,
            onSelectSingle: onSelectSingle,
            onToggleSelection: onToggleSelection,
            onExtendSelectionTo: onExtendSelectionTo,
            contextMenuActions: contextMenuActions(item.id),
            hoverCoordinator: hoverCoordinator,
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
        .accessibilityIdentifier("historyItem.\(item.id.uuidString)")
        .transition(rowTransition(index: index))

        #if DEBUG
            return row.background {
                if let viewportProbe {
                    ClipboardListViewportRowTracker(
                        itemID: item.id,
                        viewportProbe: viewportProbe
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        #else
            return row
        #endif
    }

    private func rowTransition(index: Int) -> AnyTransition {
        var insertion: AnyTransition = .opacity
        if searchResultAnimationPolicy.usesRowOffset {
            insertion = .offset(y: -4).combined(with: insertion)
        }
        if let animation = searchResultAnimationPolicy.insertion {
            let delay =
                searchResultAnimationPolicy.usesStagger
                ? min(Double(index), 12) * 0.010 : 0
            insertion = insertion.animation(animation.delay(delay))
        }
        var removal: AnyTransition = .opacity
        if let animation = searchResultAnimationPolicy.removal {
            removal = removal.animation(animation)
        }
        return .asymmetric(insertion: insertion, removal: removal)
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

private struct ClipboardPinnedRowInteraction {
    let itemID: UUID
    let nextItemID: UUID?
    let onBeginDrag: () -> Bool
    let canAcceptDrop: () -> Bool
    let onPreviewDrop: (ClipboardPinnedReorderDestination) -> Bool
    let onPerformDrop: (ClipboardPinnedReorderDestination) -> Void
    let onDragLocationChanged: (CGFloat, @escaping @MainActor () -> Void) -> Void
    let onDragEnded: () -> Void
    let onPrimaryMouseDown: (NSEvent.ModifierFlags) -> Bool
    let onClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onSecondaryClick: () -> Void
    let contextMenuActions: [HistoryItemActionDescriptor]
    let onContextMenuAction: (HistoryItemAction) -> Void
    let onContextMenuDismissed: () -> Void
}

private struct ClipboardInteractiveItemRow: View {
    let item: ClipboardItem
    let index: Int
    let websitePreviewsEnabled: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let primaryLabelText: String
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let queryPlan: ClipboardQueryPlan?
    let contentMatchClassification: ClipboardMatchClassification?
    let matchEvidence: ClipboardSearchMatchEvidence?
    let searchSnippet: ClipboardSearchSnippet?
    let isContextMenuHighlighted: Bool
    let contextMenuIsActive: Bool
    let pinnedInteraction: ClipboardPinnedRowInteraction?
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: [HistoryItemActionDescriptor]
    let hoverCoordinator: ClipboardListHoverCoordinator
    let onPrimaryInteraction: () -> Void
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void
    let onSecondaryClick: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if let pinnedInteraction {
                dragCompatibleRow(pinnedInteraction)
            } else {
                standardInteractionRow
            }
        }
        .onDisappear {
            hoverCoordinator.deactivate(itemID: item.id)
        }
    }

    private var baseRow: some View {
        ClipboardItemRow(
            item: item,
            websitePreviewsEnabled: websitePreviewsEnabled,
            primaryLabelText: primaryLabelText,
            isMultiSelected: isMultiSelected,
            joinsSelectionAbove: joinsSelectionAbove,
            joinsSelectionBelow: joinsSelectionBelow,
            selectionJoinOverlap: selectionJoinOverlap,
            quickPasteNumber: quickPasteNumber,
            queryPlan: queryPlan,
            contentMatchClassification: contentMatchClassification,
            matchEvidence: matchEvidence,
            searchSnippet: searchSnippet,
            isHovered: isHovered || isContextMenuHighlighted,
            assetProvider: assetProvider
        )
        .contentShape(Rectangle())
    }

    private var standardInteractionRow: some View {
        baseRow
            .overlay {
                ClickModifierDetector(
                    onClickWithModifiers: handlePrimaryMouseDown(modifiers:),
                    onDoubleClick: handleDoubleClick,
                    onHoverChanged: handleHoverChanged(_:),
                    onPointerMoved: handlePointerMoved,
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
                .onAppear(perform: onSecondaryClick)
            }
            .accessibilityRepresentation {
                Button(primaryLabelText) {
                    handlePrimaryMouseDown(modifiers: [])
                }
                .accessibilityIdentifier("historyItem.\(item.id.uuidString)")
                .accessibilityValue(
                    isMultiSelected
                        ? String(localized: "Selected") : String(localized: "Not selected")
                )
            }
    }

    private func dragCompatibleRow(
        _ interaction: ClipboardPinnedRowInteraction
    ) -> some View {
        baseRow
            .overlay {
                ClipboardPinnedRowDragBridge(
                    itemID: interaction.itemID,
                    nextItemID: interaction.nextItemID,
                    onBeginDrag: interaction.onBeginDrag,
                    canAcceptDrop: interaction.canAcceptDrop,
                    onPreviewDrop: interaction.onPreviewDrop,
                    onPerformDrop: interaction.onPerformDrop,
                    onDragLocationChanged: interaction.onDragLocationChanged,
                    onDragEnded: interaction.onDragEnded,
                    onPrimaryMouseDown: interaction.onPrimaryMouseDown,
                    onClickWithModifiers: interaction.onClickWithModifiers,
                    onDoubleClick: interaction.onDoubleClick,
                    onSecondaryClick: interaction.onSecondaryClick,
                    onHoverChanged: handleHoverChanged(_:),
                    onPointerMoved: handlePointerMoved,
                    contextMenuActions: interaction.contextMenuActions,
                    onContextMenuAction: interaction.onContextMenuAction,
                    onContextMenuDismissed: interaction.onContextMenuDismissed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if hovering {
            guard !contextMenuIsActive else { return }
            let didActivate = hoverCoordinator.activate(itemID: item.id) {
                setHovered(false)
            }
            setHovered(didActivate)
        } else {
            hoverCoordinator.deactivate(itemID: item.id)
            setHovered(false)
        }
    }

    private func handlePointerMoved() {
        guard !contextMenuIsActive, !isHovered else { return }
        let didActivate = hoverCoordinator.activateFromPointerMovement(itemID: item.id) {
            setHovered(false)
        }
        setHovered(didActivate)
    }

    private func setHovered(_ hovering: Bool) {
        guard isHovered != hovering else { return }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isHovered = hovering
        }
    }
}
