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
    let rows: [ClipboardListStructure.DisplayRow]
    let items: [ClipboardItem]
    let websitePreviewsEnabled: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let selectedIDs: Set<UUID>
    let searchResultsByItemID: [UUID: ClipboardSearchHit]
    let queryText: String
    let committedQueryText: String
    let searchResultAnimationID: UUID?
    let searchResultAnimationPolicy: SearchResultAnimationPolicy
    let onCommitSelection: () -> Void
    let onSelectSingle: (UUID, Int) -> Void
    let onToggleSelection: (UUID) -> Void
    let onExtendSelectionTo: (UUID) -> Void
    let contextMenuActions: (UUID) -> [HistoryItemActionDescriptor]
    let onContextMenuAction: (UUID, HistoryItemAction) -> Void

    @ObservedObject var contextMenuState: ClipboardListContextMenuState
    @ObservedObject var measuredScrollCoordinator: ClipboardMeasuredScrollCoordinator
    let hoverCoordinator: ClipboardListHoverCoordinator

    let primaryLabelText: (ClipboardItem) -> String
    let indexForItem: (ClipboardItem) -> Int

    var body: some View {
        let highlightPlan = queryText.isEmpty ? nil : ClipboardQueryPlan(queryText)
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
                itemRow(for: item, highlightPlan: highlightPlan)
            }
        }
    }

    private func itemRow(
        for item: ClipboardItem,
        highlightPlan: ClipboardQueryPlan?
    ) -> some View {
        let index = indexForItem(item)
        let previousItemID = adjacentItemID(before: index)
        let nextItemID = adjacentItemID(after: index)
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

        return ClipboardInteractiveItemRow(
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
        .transition(rowTransition(index: index))
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
        }
        .onDisappear {
            hoverCoordinator.deactivate(itemID: item.id)
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
