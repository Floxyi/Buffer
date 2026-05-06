import SwiftUI

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    private let topScrollAnchorID = "history-list-top"
    private let rowSpacing: CGFloat = 4

    @State private var padding: CGFloat = 8
    @State private var scrollbarWidth: CGFloat = 4

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

    private var hasVisibleScrollbar: Bool {
        max(0, scrollController.contentHeight - scrollController.viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        hasVisibleScrollbar
            ? scrollbarWidth + 2 * padding
            : padding
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: rowSpacing) {
                        Color.clear
                            .frame(height: 0)
                            .id(topScrollAnchorID)

                        ForEach(displayRows) { row in
                            switch row.kind {
                            case .header(let title, let systemImage):
                                ClipboardSectionHeader(
                                    title: title,
                                    systemImage: systemImage
                                )
                                .padding(.leading, padding)

                            case .divider:
                                ClipboardSectionDivider()

                            case .item(let item):
                                itemRow(for: item)
                            }
                        }
                    }
                    .padding(.vertical, padding)
                    .padding(.leading, padding)
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
                    scrollController.scrollToTop(retryCount: 6)
                }
                .onChange(of: selectedIndex) { newValue in
                    guard scrollTrigger else { return }

                    if let item = items[safe: newValue] {
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

        let trackHeight = max(0, viewportHeight - 2 * padding)
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollbarWidth: scrollbarWidth,
                scrollOffset: scrollController.scrollOffset
            ) { progress in
                scrollController.scroll(to: progress)
            }
            .frame(width: scrollbarWidth, height: trackHeight)
            .contentShape(Rectangle())
            .padding(.vertical, padding)
            .padding(.trailing, padding)
            .zIndex(10)
        }
    }

    private func itemRow(for item: ClipboardItem) -> some View {
        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0

        return ClipboardItemRow(
            item: item,
            store: store,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: index > 0 && selectedIDs.contains(items[index - 1].id),
            joinsSelectionBelow: index < items.count - 1 && selectedIDs.contains(items[index + 1].id),
            selectionJoinOverlap: rowSpacing / 2,
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
