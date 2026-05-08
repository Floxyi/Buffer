import AppKit
import SwiftUI

private enum ClipboardListCoordinateSpace {
    static let content = "ClipboardListViewContentCoordinateSpace"
}

private struct ClipboardItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    @StateObject private var scrollController = ScrollController()
    @State private var contextMenuHighlightedItemID: UUID?
    @State private var scrollRequestID: UInt = 0
    @State private var itemFramesByID: [UUID: CGRect] = [:]

    let items: [ClipboardItem]

    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool

    let store: ClipboardStore
    let showsQuickPasteNumbers: Bool
    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    // Multi-select support
    @Binding var selectedIDs: Set<UUID>
    @Binding var hoveredItemID: UUID?
    var onSelectSingle: (UUID) -> Void = { _ in }
    var onToggleSelection: (UUID) -> Void = { _ in }
    var onExtendSelectionTo: (UUID) -> Void = { _ in }
    var onCopyItem: (ClipboardItem) -> Void = { _ in }
    var onTogglePinItem: (ClipboardItem) -> Void = { _ in }
    var onDeleteItem: (ClipboardItem) -> Void = { _ in }
    var onJumpToHistoryItem: ((ClipboardItem) -> Void)? = nil
    var showsJumpToHistoryAction = false
    var selectionNavigationToken: Int = 0
    var selectedItemID: UUID? = nil
    var openScrollRequest: HistoryViewModel.OpenListScrollRequest? = nil
    var openScrollRequestToken: Int = 0
    var onScrollOffsetChanged: (CGFloat) -> Void = { _ in }

    private var displayRows: [ClipboardListStructure.DisplayRow] {
        ClipboardListStructure.displayRows(from: items)
    }

    private var itemIDs: [UUID] {
        items.map(\.id)
    }

    private var itemIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        hasVisibleScrollbar
            ? ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2 * ClipboardListStructure.LayoutMetrics.contentPadding
            : ClipboardListStructure.LayoutMetrics.contentPadding
    }

    private var highlightedItemID: UUID? {
        contextMenuHighlightedItemID ?? hoveredItemID
    }

    var body: some View {
        VStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: ClipboardListStructure.LayoutMetrics.rowSpacing) {
                    ForEach(displayRows) { row in
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
                .padding(.vertical, ClipboardListStructure.LayoutMetrics.contentPadding)
                .padding(.leading, ClipboardListStructure.LayoutMetrics.contentPadding)
                .padding(.trailing, contentTrailingPadding)
                .coordinateSpace(name: ClipboardListCoordinateSpace.content)
                .background {
                    ScrollViewConfigurator(
                        configure: { scrollView in
                            scrollView.hasVerticalScroller = false
                            scrollView.autohidesScrollers = true
                            scrollView.scrollerStyle = .overlay

                            scrollView.automaticallyAdjustsContentInsets = false
                            scrollView.verticalScrollElasticity = .none
                            scrollView.horizontalScrollElasticity = .none

                            scrollController.configure(
                                scrollView: scrollView,
                                enablesWheelSmoothing: false
                            )
                        },
                        searchStrategy: .nearestAncestorOnly
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                scrollToTopButton
            }
            .overlay(alignment: .topTrailing) {
                customScrollbar
            }
            .onPreferenceChange(ClipboardItemFramePreferenceKey.self) { frames in
                itemFramesByID = frames
            }
            .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                contextMenuHighlightedItemID = nil
            }
            .onAppear {
                scrollController.setContentHeightOverride(nil)
            }
            .onChange(of: scrollController.scrollOffset) { newValue in
                onScrollOffsetChanged(newValue)
            }
            .onChange(of: itemIDs) { _ in
                guard let openScrollRequest else { return }
                guard case .scrollToItem(let itemID) = openScrollRequest.mode else { return }

                scheduleMeasuredScroll(to: itemID, centered: true)
            }
            .onChange(of: openScrollRequestToken) { _ in
                guard let openScrollRequest else { return }
                applyOpenScrollRequest(openScrollRequest)
            }
            .onChange(of: selectedIndex) { newValue in
                guard scrollTrigger else { return }
                scrollTrigger = false

                if newValue == 0 {
                    scrollController.scrollToTop(retryCount: 2)
                } else if let itemID = items[safe: newValue]?.id {
                    scheduleMeasuredScroll(to: itemID, centered: false)
                }
            }
            .onChange(of: selectionNavigationToken) { _ in
                guard let selectedItemID else { return }
                scheduleMeasuredScroll(to: selectedItemID, centered: true)
            }
        }
    }

    @ViewBuilder
    private var scrollToTopButton: some View {
        let viewportHeight = scrollController.viewportHeight
        let scrollOffset = scrollController.scrollOffset

        if scrollOffset > max(80, viewportHeight * 0.35) {
            ClipboardScrollToTopButton {
                selectFirstItemAndScrollToTop()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var customScrollbar: some View {
        let viewportHeight = scrollController.viewportHeight
        let contentHeight = scrollController.contentHeight

        let trackHeight = max(
            0,
            viewportHeight - 2 * ClipboardListStructure.LayoutMetrics.contentPadding
        )
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollbarWidth: ClipboardListStructure.LayoutMetrics.scrollbarWidth,
                scrollOffset: scrollController.scrollOffset
            ) { progress in
                scrollController.scroll(to: progress)
            }
            .frame(width: ClipboardListStructure.LayoutMetrics.scrollbarWidth, height: trackHeight)
            .contentShape(Rectangle())
            .padding(.vertical, ClipboardListStructure.LayoutMetrics.contentPadding)
            .padding(.trailing, ClipboardListStructure.LayoutMetrics.contentPadding)
            .zIndex(10)
        }
    }

    private func itemRow(for item: ClipboardItem) -> some View {
        let index = itemIndexByID[item.id] ?? 0

        return ClipboardItemRow(
            item: item,
            store: store,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: index > 0 && selectedIDs.contains(items[index - 1].id),
            joinsSelectionBelow: index < items.count - 1 && selectedIDs.contains(items[index + 1].id),
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: showsQuickPasteNumbers && index < 5 ? index + 1 : nil,
            isHovered: highlightedItemID == item.id
        )
        .id(item.id)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ClipboardItemFramePreferenceKey.self,
                    value: [
                        item.id: proxy.frame(in: .named(ClipboardListCoordinateSpace.content))
                    ]
                )
            }
        }
        .contentShape(Rectangle())
        .overlay(
            ClickModifierDetector { modifiers in
                contextMenuHighlightedItemID = nil
                selectedIndex = index

                if modifiers.hasCommand {
                    onToggleSelection(item.id)
                } else if modifiers.hasShift {
                    onExtendSelectionTo(item.id)
                } else {
                    onSelectSingle(item.id)
                }
            } onHoverChanged: { hovering in
                guard contextMenuHighlightedItemID == nil || !hovering else { return }
                hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            } onSecondaryClick: {
                hoveredItemID = nil
                contextMenuHighlightedItemID = item.id
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
                    selectedIndex = index
                    onSelect(item)
                    onDismiss()
                }
        )
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") {
                contextMenuHighlightedItemID = nil
                selectedIndex = index
                onSelectSingle(item.id)
                onCopyItem(item)
            }

            Button(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin") {
                contextMenuHighlightedItemID = nil
                selectedIndex = index
                onTogglePinItem(item)
            }

            if showsJumpToHistoryAction, let onJumpToHistoryItem {
                Button("Jump to History", systemImage: "arrow.turn.down.right") {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onJumpToHistoryItem(item)
                }
            }

            Divider()

            Button("Delete", systemImage: "trash", role: .destructive) {
                contextMenuHighlightedItemID = nil
                selectedIndex = index
                onDeleteItem(item)
            }
        }
    }

    private func scheduleMeasuredScroll(to itemID: UUID, centered: Bool) {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        Task { @MainActor in
            for attempt in 0..<12 {
                guard requestID == scrollRequestID else { return }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }

                guard itemIndexByID[itemID] != nil else {
                    continue
                }

                scrollController.syncMetricsImmediately()

                guard let frame = itemFramesByID[itemID] else {
                    continue
                }

                let viewportHeight = max(1, scrollController.viewportHeight)
                let targetY = centered
                    ? viewportHeight / 2
                    : viewportHeight * 0.35

                let targetOffset = frame.midY - targetY

                scrollController.scrollTo(offset: targetOffset)

                await Task.yield()
                scrollController.syncMetricsImmediately()

                let expectedOffset = max(
                    0,
                    min(
                        targetOffset,
                        max(0, scrollController.contentHeight - scrollController.viewportHeight)
                    )
                )

                if abs(scrollController.scrollOffset - expectedOffset) <= 2 {
                    return
                }
            }
        }
    }

    private func selectFirstItemAndScrollToTop() {
        guard let firstItem = items.first else {
            scrollController.scrollToTopImmediately()
            return
        }

        contextMenuHighlightedItemID = nil
        hoveredItemID = nil
        selectedIndex = 0
        onSelectSingle(firstItem.id)
        scrollController.scrollToTopImmediately()
    }

    private func applyOpenScrollRequest(_ request: HistoryViewModel.OpenListScrollRequest) {
        switch request.mode {
        case .scrollToTop:
            scrollController.scrollToTopImmediately()

        case .restoreOffset(let offset):
            Task { @MainActor in
                await Task.yield()
                scrollController.scrollTo(offset: offset)
            }

        case .scrollToItem(let itemID):
            scheduleMeasuredScroll(to: itemID, centered: true)
        }
    }
}
