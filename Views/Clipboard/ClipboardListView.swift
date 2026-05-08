import AppKit
import SwiftUI

private enum ClipboardListCoordinateSpace {
    static let content = "ClipboardListViewContentCoordinateSpace"
}

private struct ClipboardScrollTargetFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct PendingMeasuredScrollTarget: Equatable {
    let itemID: UUID
    let centered: Bool
    let requestID: UInt
}

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    @State private var scrollController = ScrollController()
    @State private var contextMenuHighlightedItemID: UUID?
    @State private var scrollRequestID: UInt = 0
    @State private var pendingMeasuredScrollTarget: PendingMeasuredScrollTarget?
    @State private var measuredTargetFrame: CGRect?
    @State private var listCache = ClipboardListStructure.DisplayCache.empty
    @State private var rowAssetsByID: [UUID: ClipboardItemRowAssets] = [:]
    @State private var loadedAssetItemIDs: Set<UUID> = []
    @State private var rowAssetLoadTask: Task<Void, Never>?

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

    private var itemIDs: [UUID] {
        items.map(\.id)
    }

    private var displayRowsForRendering: [ClipboardListStructure.DisplayRow] {
        if listCache.matches(items: items) {
            return listCache.displayRows
        }

        return ClipboardListStructure.displayRows(from: items)
    }

    private var contentTrailingPadding: CGFloat {
        ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2 * ClipboardListStructure.LayoutMetrics.contentPadding
    }

    private var highlightedItemID: UUID? {
        contextMenuHighlightedItemID ?? hoveredItemID
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: ClipboardListStructure.LayoutMetrics.rowSpacing) {
                        ForEach(displayRowsForRendering) { row in
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
                    ClipboardScrollToTopOverlay(scrollController: scrollController) {
                        selectFirstItemAndScrollToTop()
                    }
                }
                .overlay(alignment: .topTrailing) {
                    ClipboardScrollbarOverlay(scrollController: scrollController)
                }
                .background {
                    ZStack {
                        ClipboardScrollOffsetObserver(
                            scrollController: scrollController,
                            onScrollOffsetChanged: onScrollOffsetChanged
                        )

                        ClipboardScrollActivityObserver(
                            scrollActivityTracker: scrollController.activityTracker
                        ) { isScrolling in
                            guard !isScrolling else { return }
                            scheduleRowAssetLoadForCurrentViewport()
                        }
                    }
                }
                .onPreferenceChange(ClipboardScrollTargetFramePreferenceKey.self) { frame in
                    measuredTargetFrame = frame

                    guard let pendingMeasuredScrollTarget,
                          pendingMeasuredScrollTarget.requestID == scrollRequestID else {
                        return
                    }

                    if performExactMeasuredScroll(
                        to: pendingMeasuredScrollTarget.itemID,
                        centered: pendingMeasuredScrollTarget.centered
                    ) {
                        self.pendingMeasuredScrollTarget = nil
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                    contextMenuHighlightedItemID = nil
                }
                .onAppear {
                    rebuildListCache()
                    pruneRowAssetState()
                    scheduleRowAssetLoadForCurrentViewport()
                    scrollController.setContentHeightOverride(nil)
                }
                .onDisappear {
                    rowAssetLoadTask?.cancel()
                    rowAssetLoadTask = nil
                }
                .onChange(of: itemIDs) { _ in
                    rebuildListCache()
                    pruneRowAssetState()
                    scheduleRowAssetLoadForCurrentViewport()

                    guard let openScrollRequest else { return }
                    guard case .scrollToItem(let itemID) = openScrollRequest.mode else { return }

                    scheduleMeasuredScroll(
                        to: itemID,
                        centered: true,
                        using: scrollProxy
                    )
                }
                .onChange(of: openScrollRequestToken) { _ in
                    guard let openScrollRequest else { return }
                    applyOpenScrollRequest(openScrollRequest, using: scrollProxy)
                }
                .onChange(of: selectedIndex) { newValue in
                    guard scrollTrigger else { return }
                    scrollTrigger = false

                    if newValue == 0 {
                        scrollController.scrollToTop(retryCount: 2)
                    } else if let itemID = items[safe: newValue]?.id {
                        scheduleMeasuredScroll(
                            to: itemID,
                            centered: false,
                            using: scrollProxy
                        )
                    }
                }
                .onChange(of: selectionNavigationToken) { _ in
                    guard let selectedItemID else { return }

                    scheduleMeasuredScroll(
                        to: selectedItemID,
                        centered: true,
                        using: scrollProxy
                    )
                }
            }
        }
    }

    private func itemRow(for item: ClipboardItem) -> some View {
        let index = index(for: item)
        let previousItemID = adjacentItemID(before: index)
        let nextItemID = adjacentItemID(after: index)

        return ClipboardItemRow(
            item: item,
            primaryLabelText: primaryLabelText(for: item),
            assets: rowAssets(for: item),
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: previousItemID.map { selectedIDs.contains($0) } ?? false,
            joinsSelectionBelow: nextItemID.map { selectedIDs.contains($0) } ?? false,
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: showsQuickPasteNumbers && index < 5 ? index + 1 : nil,
            isHovered: highlightedItemID == item.id
        )
        .id(item.id)
        .background {
            if pendingMeasuredScrollTarget?.itemID == item.id {
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
                guard !scrollController.activityTracker.isScrolling else { return }
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

    private func scheduleMeasuredScroll(
        to itemID: UUID,
        centered: Bool,
        using scrollProxy: ScrollViewProxy
    ) {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        measuredTargetFrame = nil
        pendingMeasuredScrollTarget = PendingMeasuredScrollTarget(
            itemID: itemID,
            centered: centered,
            requestID: requestID
        )

        Task { @MainActor in
            let attemptCount = centered ? 10 : 5
            let anchor: UnitPoint = centered ? .center : UnitPoint(x: 0.5, y: 0.5)

            for attempt in 0..<attemptCount {
                guard requestID == scrollRequestID else { return }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                guard itemExists(itemID) else {
                    continue
                }

                scrollController.syncMetricsImmediately()

                let shouldUseProxyScroll: Bool
                if centered {
                    shouldUseProxyScroll = measuredTargetFrame == nil || attempt < 2
                } else {
                    shouldUseProxyScroll = measuredTargetFrame == nil && attempt >= 2
                }

                if shouldUseProxyScroll {
                    withAnimation(nil) {
                        scrollProxy.scrollTo(itemID, anchor: anchor)
                    }
                }

                await Task.yield()
                try? await Task.sleep(nanoseconds: 12_000_000)

                if performExactMeasuredScroll(to: itemID, centered: centered) {
                    pendingMeasuredScrollTarget = nil
                    scheduleRowAssetLoadForCurrentViewport()
                    return
                }
            }
        }
    }

    @discardableResult
    private func performExactMeasuredScroll(to itemID: UUID, centered: Bool) -> Bool {
        guard pendingMeasuredScrollTarget?.itemID == itemID,
              let measuredTargetFrame else {
            return false
        }

        scrollController.syncMetricsImmediately()

        let viewportHeight = max(1, scrollController.viewportHeight)
        let currentOffset = scrollController.scrollOffset
        let maxOffset = max(0, scrollController.contentHeight - viewportHeight)

        let targetOffset: CGFloat

        if centered {
            let targetY = viewportHeight / 2
            targetOffset = measuredTargetFrame.midY - targetY
        } else {
            let edgePadding = CGFloat(10)
            let visibleMinY = currentOffset + edgePadding
            let visibleMaxY = currentOffset + viewportHeight - edgePadding

            if measuredTargetFrame.minY >= visibleMinY,
               measuredTargetFrame.maxY <= visibleMaxY {
                return true
            }

            if measuredTargetFrame.minY < visibleMinY {
                targetOffset = measuredTargetFrame.minY - edgePadding
            } else {
                targetOffset = measuredTargetFrame.maxY - viewportHeight + edgePadding
            }
        }

        let clampedTargetOffset = targetOffset.clamped(to: 0...maxOffset)

        guard abs(scrollController.scrollOffset - clampedTargetOffset) > 1 else {
            return true
        }

        scrollController.scrollTo(offset: clampedTargetOffset)
        scrollController.syncMetricsImmediately()

        return abs(scrollController.scrollOffset - clampedTargetOffset) <= 2
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
        scheduleRowAssetLoadForCurrentViewport()
    }

    private func applyOpenScrollRequest(
        _ request: HistoryViewModel.OpenListScrollRequest,
        using scrollProxy: ScrollViewProxy
    ) {
        switch request.mode {
        case .scrollToTop:
            scrollController.scrollToTopImmediately()
            scheduleRowAssetLoadForCurrentViewport()

        case .restoreOffset(let offset):
            Task { @MainActor in
                await Task.yield()
                scrollController.scrollTo(offset: offset)
                scheduleRowAssetLoadForCurrentViewport()
            }

        case .scrollToItem(let itemID):
            scheduleMeasuredScroll(
                to: itemID,
                centered: true,
                using: scrollProxy
            )
        }
    }

    private func rebuildListCache() {
        listCache = ClipboardListStructure.makeDisplayCache(from: items)
    }

    private func scheduleRowAssetLoadForCurrentViewport() {
        rowAssetLoadTask?.cancel()

        rowAssetLoadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)

            guard !Task.isCancelled else { return }
            guard !scrollController.activityTracker.isScrolling else { return }

            let candidates = assetLoadCandidates(limit: 90)
            await loadAssets(for: candidates)
        }
    }

    private func loadAssets(for candidates: [ClipboardItem]) async {
        guard !candidates.isEmpty else { return }

        var nextAssetsByID = rowAssetsByID
        var nextLoadedAssetItemIDs = loadedAssetItemIDs
        var pendingUpdates = 0

        for item in candidates {
            guard !Task.isCancelled else { return }
            guard !scrollController.activityTracker.isScrolling else { return }
            guard !nextLoadedAssetItemIDs.contains(item.id) else { continue }

            let assets = await ClipboardItemRowAssetLoader.loadAssets(
                for: item,
                store: store,
                leadingVisualSize: 28
            )

            guard !Task.isCancelled else { return }
            guard !scrollController.activityTracker.isScrolling else { return }

            nextAssetsByID[item.id] = assets
            nextLoadedAssetItemIDs.insert(item.id)
            pendingUpdates += 1

            if pendingUpdates >= 12 {
                rowAssetsByID = nextAssetsByID
                loadedAssetItemIDs = nextLoadedAssetItemIDs
                pendingUpdates = 0
                await Task.yield()
            }
        }

        if pendingUpdates > 0 {
            rowAssetsByID = nextAssetsByID
            loadedAssetItemIDs = nextLoadedAssetItemIDs
        }
    }

    private func assetLoadCandidates(limit: Int) -> [ClipboardItem] {
        let rows = listCache.matches(items: items)
            ? listCache.displayRows
            : ClipboardListStructure.displayRows(from: items)

        let visibleIDs = ClipboardListStructure.visibleItemIDs(
            in: rows,
            scrollOffset: scrollController.scrollOffset,
            viewportHeight: scrollController.viewportHeight,
            overscan: 320
        )

        var result: [ClipboardItem] = []
        var seenIDs = Set<UUID>()

        for id in visibleIDs {
            appendCandidate(
                id: id,
                to: &result,
                seenIDs: &seenIDs,
                limit: limit
            )
        }

        if let selectedItemID {
            appendCandidateWindow(
                around: selectedItemID,
                radius: 16,
                to: &result,
                seenIDs: &seenIDs,
                limit: limit
            )
        }

        for item in items.prefix(30) {
            appendCandidate(
                item,
                to: &result,
                seenIDs: &seenIDs,
                limit: limit
            )
        }

        return result
    }

    private func appendCandidateWindow(
        around itemID: UUID,
        radius: Int,
        to result: inout [ClipboardItem],
        seenIDs: inout Set<UUID>,
        limit: Int
    ) {
        guard let index = listCache.itemIndexByID[itemID],
              items.indices.contains(index) else {
            return
        }

        let lowerBound = max(items.startIndex, index - radius)
        let upperBound = min(items.index(before: items.endIndex), index + radius)

        for itemIndex in lowerBound...upperBound {
            appendCandidate(
                items[itemIndex],
                to: &result,
                seenIDs: &seenIDs,
                limit: limit
            )

            if result.count >= limit {
                return
            }
        }
    }

    private func appendCandidate(
        id itemID: UUID,
        to result: inout [ClipboardItem],
        seenIDs: inout Set<UUID>,
        limit: Int
    ) {
        guard let index = listCache.itemIndexByID[itemID],
              items.indices.contains(index) else {
            return
        }

        appendCandidate(
            items[index],
            to: &result,
            seenIDs: &seenIDs,
            limit: limit
        )
    }

    private func appendCandidate(
        _ item: ClipboardItem,
        to result: inout [ClipboardItem],
        seenIDs: inout Set<UUID>,
        limit: Int
    ) {
        guard result.count < limit else { return }
        guard seenIDs.insert(item.id).inserted else { return }
        guard !loadedAssetItemIDs.contains(item.id) else { return }

        result.append(item)
    }

    private func pruneRowAssetState() {
        let currentItemIDs = Set(items.map(\.id))

        rowAssetsByID = rowAssetsByID.filter { currentItemIDs.contains($0.key) }
        loadedAssetItemIDs = loadedAssetItemIDs.intersection(currentItemIDs)
    }

    private func rowAssets(for item: ClipboardItem) -> ClipboardItemRowAssets {
        rowAssetsByID[item.id] ?? .empty
    }

    private func primaryLabelText(for item: ClipboardItem) -> String {
        listCache.primaryLabelText(for: item)
    }

    private func index(for item: ClipboardItem) -> Int {
        listCache.index(for: item, in: items)
    }

    private func itemExists(_ itemID: UUID) -> Bool {
        listCache.itemExists(itemID, in: items)
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

private struct ClipboardScrollOffsetObserver: View {
    @ObservedObject var scrollController: ScrollController
    let onScrollOffsetChanged: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: scrollController.scrollOffset) { newValue in
                onScrollOffsetChanged(newValue)
            }
    }
}

private struct ClipboardScrollActivityObserver: View {
    @ObservedObject var scrollActivityTracker: ScrollActivityTracker
    let onScrollingChanged: (Bool) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: scrollActivityTracker.isScrolling) { isScrolling in
                onScrollingChanged(isScrolling)
            }
    }
}

private struct ClipboardScrollToTopOverlay: View {
    @ObservedObject var scrollController: ScrollController
    let onSelectTop: () -> Void

    var body: some View {
        let viewportHeight = scrollController.viewportHeight
        let scrollOffset = scrollController.scrollOffset

        if scrollOffset > max(80, viewportHeight * 0.35) {
            ClipboardScrollToTopButton {
                onSelectTop()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private struct ClipboardScrollbarOverlay: View {
    @ObservedObject var scrollController: ScrollController

    var body: some View {
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
            .frame(
                width: ClipboardListStructure.LayoutMetrics.scrollbarWidth,
                height: trackHeight
            )
            .contentShape(Rectangle())
            .padding(.vertical, ClipboardListStructure.LayoutMetrics.contentPadding)
            .padding(.trailing, ClipboardListStructure.LayoutMetrics.contentPadding)
            .zIndex(10)
        }
    }
}
