import SwiftUI

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    private let topScrollAnchorID = "history-list-top-anchor"

    @StateObject private var scrollController = ScrollController()

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
    var resetScrollToken: Int = 0

    private var displayRows: [ClipboardListStructure.DisplayRow] {
        ClipboardListStructure.displayRows(from: items)
    }

    private var itemIndexByID: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
    }

    private var estimatedContentHeight: CGFloat {
        ClipboardListStructure.estimatedContentHeight(for: displayRows)
    }

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        hasVisibleScrollbar
            ? ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2 * ClipboardListStructure.LayoutMetrics.contentPadding
            : ClipboardListStructure.LayoutMetrics.contentPadding
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Color.clear
                        .frame(height: 0)
                        .id(topScrollAnchorID)

                    LazyVStack(spacing: ClipboardListStructure.LayoutMetrics.rowSpacing) {
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
                }
                .background {
                    ScrollViewConfigurator { scrollView in
                        scrollView.hasVerticalScroller = false
                        scrollView.autohidesScrollers = true
                        scrollView.scrollerStyle = .overlay

                        scrollView.automaticallyAdjustsContentInsets = false
                        scrollView.verticalScrollElasticity = .none
                        scrollView.horizontalScrollElasticity = .none

                        scrollController.configure(scrollView: scrollView)
                    }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    scrollToTopButton
                }
                .overlay(alignment: .topTrailing) {
                    customScrollbar
                }
                .onAppear {
                    scrollController.setContentHeightOverride(estimatedContentHeight)
                    scrollController.scrollToTop(retryCount: 6)
                }
                .onChange(of: estimatedContentHeight) { newValue in
                    scrollController.setContentHeightOverride(newValue)
                }
                .onChange(of: selectedIndex) { newValue in
                    guard scrollTrigger else { return }

                    if newValue == 0 {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(topScrollAnchorID, anchor: .top)
                        }
                    } else if let item = items[safe: newValue] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(item.id)
                        }
                    }

                    scrollTrigger = false

                    Task { @MainActor in
                        await Task.yield()
                        scrollController.syncMetrics()
                    }
                }
                .onChange(of: resetScrollToken) { _ in
                    scrollController.scrollToTop(retryCount: 6)
                }
            }
        }
    }

    @ViewBuilder
    private var scrollToTopButton: some View {
        let viewportHeight = scrollController.viewportHeight
        let scrollOffset = scrollController.scrollOffset

        if scrollOffset > max(80, viewportHeight * 0.35) {
            ClipboardScrollToTopButton {
                scrollController.scrollToTopImmediately()
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
            isHovered: hoveredItemID == item.id
        )
        .id(item.id)
        .contentShape(Rectangle())
        .overlay(
            ClickModifierDetector { modifiers in
                selectedIndex = index

                if modifiers.hasCommand {
                    onToggleSelection(item.id)
                } else if modifiers.hasShift {
                    onExtendSelectionTo(item.id)
                } else {
                    onSelectSingle(item.id)
                }
            } onHoverChanged: { hovering in
                hoveredItemID = hovering ? item.id : nil
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
    }
}
