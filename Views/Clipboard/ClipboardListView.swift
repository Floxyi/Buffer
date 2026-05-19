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

private struct JumpScrollTaskKey: Equatable {
    let request: HistoryViewModel.JumpToHistoryRequest?
    let itemCount: Int
    let isShowingFullHistory: Bool
}

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    private static let keyboardNavigationComfortPadding = ClipboardListStructure.LayoutMetrics.itemRowHeight
    private static let keyboardNavigationTopSnapThreshold =
        ClipboardListStructure.LayoutMetrics.contentPadding +
        ClipboardListStructure.LayoutMetrics.sectionHeaderHeight +
        ClipboardListStructure.LayoutMetrics.rowSpacing +
        ClipboardListStructure.LayoutMetrics.itemRowHeight
    private static let rapidKeyboardNavigationThreshold = 0.12

    @StateObject private var scrollController = ScrollController()
    @State private var contextMenuHighlightedItemID: UUID?
    @State private var scrollRequestID: UInt = 0
    @State private var pendingMeasuredScrollTarget: PendingMeasuredScrollTarget?
    @State private var pendingMeasuredScrollCompletion: ((Bool) -> Void)?
    @State private var measuredScrollTask: Task<Void, Never>?
    @State private var keyboardNavigationScrollTask: Task<Void, Never>?
    @State private var keyboardNavigationCommitTask: Task<Void, Never>?
    @State private var measuredTargetFrame: CGRect?
    @State private var listCache = ClipboardListStructure.DisplayCache.empty
    @State private var assetPrewarmTask: Task<Void, Never>?
    @State private var keyboardAssetPrewarmTask: Task<Void, Never>?
    @State private var activeJumpScrollRequest: HistoryViewModel.JumpToHistoryRequest?
    @State private var sourceIconRefreshToken = 0
    @State private var lastKeyboardNavigationRequestTimestamp = 0.0
    @State private var isAwaitingInitialOpenScroll = false
    @State private var lastAppliedOpenScrollRequestToken = -1

    let items: [ClipboardItem]

    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool

    let store: ClipboardStore
    let settings: SettingsManager
    let quickPasteBadgeNumberByItemID: [UUID: Int]
    let onCommitSelection: () -> Void
    let onDismiss: () -> Void

    @Binding var selectedIDs: Set<UUID>
    @Binding var hoveredItemID: UUID?

    var onSelectSingle: (UUID) -> Void = { _ in }
    var onSelectPreferredTopItem: () -> UUID? = { nil }
    var onToggleSelection: (UUID) -> Void = { _ in }
    var onExtendSelectionTo: (UUID) -> Void = { _ in }
    var onPasteItems: (UUID) -> Void = { _ in }
    var onCopyItems: (UUID) -> Void = { _ in }
    var onTogglePinItems: (UUID) -> Void = { _ in }
    var onDeleteItems: (UUID) -> Void = { _ in }
    var isContextMenuTargetFullyPinned: (UUID) -> Bool = { _ in false }
    var onJumpToHistoryItem: ((ClipboardItem) -> Void)? = nil
    var showsJumpToHistoryAction = false
    var selectionNavigationToken: Int = 0
    var selectedItemID: UUID? = nil
    var openScrollRequest: HistoryViewModel.OpenListScrollRequest? = nil
    var openScrollRequestToken: Int = 0
    var isShowingFullHistory = false
    var keyboardNavigationRequest: HistoryViewModel.KeyboardNavigationRequest? = nil
    var onCompleteKeyboardNavigation: (HistoryViewModel.KeyboardNavigationRequest) -> Void = { _ in }

    /// Dedicated jump-to-history request. This must stay separate from open/keyboard scrolling.
    var jumpScrollRequest: HistoryViewModel.JumpToHistoryRequest? = nil
    var onJumpScrollStarted: (HistoryViewModel.JumpToHistoryRequest) -> Void = { _ in }
    var onJumpScrollCompleted: (HistoryViewModel.JumpToHistoryRequest, Bool) -> Void = { _, _ in }

    var onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void) = { _ in }
    var onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void) = { _ in }

    private var itemIDs: [UUID] {
        items.map(\.id)
    }

    private var jumpScrollTaskKey: JumpScrollTaskKey {
        JumpScrollTaskKey(
            request: jumpScrollRequest,
            itemCount: items.count,
            isShowingFullHistory: isShowingFullHistory
        )
    }

    private var displayRowsForRendering: [ClipboardListStructure.DisplayRow] {
        if listCache.matches(items: items) {
            return listCache.displayRows
        }

        return ClipboardListStructure.displayRows(from: items)
    }

    private var estimatedRenderedContentHeight: CGFloat {
        ClipboardListStructure.estimatedContentHeight(for: displayRowsForRendering)
    }

    private var hasVisibleScrollbar: Bool {
        let viewportHeight = scrollController.viewportHeight
        guard viewportHeight > 1 else {
            return false
        }

        return max(0, estimatedRenderedContentHeight - viewportHeight) > 1
    }

    private var contentTrailingPadding: CGFloat {
        if hasVisibleScrollbar {
            return ClipboardListStructure.LayoutMetrics.scrollbarWidth + 2 * ClipboardListStructure.LayoutMetrics.contentPadding
        }

        return ClipboardListStructure.LayoutMetrics.contentPadding
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
                        selectFirstItemAndScrollToTop(using: scrollProxy)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    ClipboardScrollbarOverlay(scrollController: scrollController)
                }
                .opacity(isAwaitingInitialOpenScroll ? 0 : 1)
                .onPreferenceChange(ClipboardScrollTargetFramePreferenceKey.self) { frame in
                    measuredTargetFrame = frame

                    guard let pendingMeasuredScrollTarget else {
                        return
                    }

                    guard pendingMeasuredScrollTarget.requestID == scrollRequestID else {
                        return
                    }

                    if performExactMeasuredScroll(
                        to: pendingMeasuredScrollTarget.itemID,
                        centered: pendingMeasuredScrollTarget.centered
                    ) {
                        finishMeasuredScroll(
                            requestID: pendingMeasuredScrollTarget.requestID,
                            succeeded: true
                        )
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
                    contextMenuHighlightedItemID = nil
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    refreshVisibleSourceApplicationIcons()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)) { _ in
                    refreshVisibleSourceApplicationIcons()
                }
                .onAppear {
                    rebuildListCache()
                    prewarmVisibleAssets()
                    onScrollOffsetProviderChanged {
                        scrollController.syncMetricsImmediately()
                        return scrollController.currentScrollOffsetSnapshot()
                    }
                    onScrollOffsetRestorerChanged { offset in
                        restoreScrollOffsetForReopen(offset)
                    }
                    applyOpenScrollRequestIfNeeded(using: scrollProxy)
                }
                .onDisappear {
                    assetPrewarmTask?.cancel()
                    assetPrewarmTask = nil
                    keyboardAssetPrewarmTask?.cancel()
                    keyboardAssetPrewarmTask = nil
                    cancelPendingMeasuredScroll()
                    cancelKeyboardNavigationScroll()
                    cancelKeyboardNavigationCommit()
                    onScrollOffsetProviderChanged(nil)
                    onScrollOffsetRestorerChanged(nil)
                }
                .onChange(of: itemIDs) { _ in
                    rebuildListCache()
                    prewarmVisibleAssets()
                }
                .onChange(of: openScrollRequestToken) { _ in
                    applyOpenScrollRequestIfNeeded(using: scrollProxy)
                }
                .onChange(of: selectedIndex) { newValue in
                    guard scrollTrigger else { return }

                    scrollTrigger = false

                    if newValue == 0 {
                        scheduleScrollToTop()
                    } else if newValue == items.count - 1 {
                        scheduleScrollToBottom()
                    } else if let itemID = items[safe: newValue]?.id {
                        scheduleKeyboardNavigationScroll(to: itemID)
                    }
                }
                .onChange(of: selectionNavigationToken) { _ in
                    guard let selectedItemID else { return }

                    if jumpScrollRequest?.itemID == selectedItemID {
                        return
                    }

                    scheduleMeasuredScroll(
                        to: selectedItemID,
                        centered: true,
                        using: scrollProxy
                    )
                }
                .onChange(of: keyboardNavigationRequest) { newRequest in
                    guard let newRequest else {
                        keyboardAssetPrewarmTask?.cancel()
                        keyboardAssetPrewarmTask = nil
                        cancelKeyboardNavigationCommit()
                        return
                    }

                    prewarmAssetsForKeyboardNavigation(request: newRequest)
                    scheduleKeyboardNavigationCommit(for: newRequest)
                }
                .onChange(of: jumpScrollRequest) { newRequest in
                    if activeJumpScrollRequest != nil,
                       activeJumpScrollRequest != newRequest {
                        activeJumpScrollRequest = nil
                    }
                }
                .task(id: jumpScrollTaskKey) {
                    guard let jumpScrollRequest else {
                        return
                    }

                    await waitAndStartJumpScrollIfReady(
                        jumpScrollRequest,
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
        var menuItem = item
        menuItem.isPinned = isContextMenuTargetFullyPinned(item.id)

        return ClipboardItemRow(
            item: item,
            store: store,
            settings: settings,
            primaryLabelText: primaryLabelText(for: item),
            scrollActivityTracker: scrollController.activityTracker,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: previousItemID.map { selectedIDs.contains($0) } ?? false,
            joinsSelectionBelow: nextItemID.map { selectedIDs.contains($0) } ?? false,
            selectionJoinOverlap: ClipboardListStructure.LayoutMetrics.rowSpacing / 2,
            quickPasteNumber: quickPasteBadgeNumberByItemID[item.id],
            isHovered: highlightedItemID == item.id,
            sourceIconRefreshToken: sourceIconRefreshToken
        )
        .id(scrollID(forItemID: item.id))
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
                    onSelectSingle(item.id)
                    onCommitSelection()
                }
        )
        .contextMenu {
            ClipboardItemActionMenuContent(
                item: menuItem,
                onPaste: {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onPasteItems(item.id)
                },
                onCopy: {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onCopyItems(item.id)
                },
                onTogglePin: {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onTogglePinItems(item.id)
                },
                onDelete: {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onDeleteItems(item.id)
                },
                onJumpToHistory: showsJumpToHistoryAction ? {
                    contextMenuHighlightedItemID = nil
                    selectedIndex = index
                    onJumpToHistoryItem?(item)
                } : nil
            )
        }
    }

    private func refreshVisibleSourceApplicationIcons() {
        ClipboardItemRowAssetLoader.clearSourceApplicationIconCache()
        sourceIconRefreshToken &+= 1
    }

    private func waitAndStartJumpScrollIfReady(
        _ request: HistoryViewModel.JumpToHistoryRequest,
        using scrollProxy: ScrollViewProxy
    ) async {
        // Jump-to-history intentionally waits until the full-history list is rendered.
        // Do not route this through openListScrollRequest; that can fire before the
        // search result list has transitioned back to the full list.
        for attempt in 0..<12 {
            guard jumpScrollRequest == request else {
                return
            }

            if attempt == 0 {
                await Task.yield()
            } else {
                try? await Task.sleep(nanoseconds: 70_000_000)
            }

            guard !Task.isCancelled else {
                return
            }

            rebuildListCache()
            scrollController.syncMetricsImmediately()

            let fullHistoryReady = isShowingFullHistory
            let targetExists = itemExists(request.itemID)

            logScrollDiagnostics(
                "Jump list check item=\(request.itemID.uuidString) generation=\(request.generation) attempt=\(attempt) fullHistoryReady=\(fullHistoryReady) targetExists=\(targetExists)"
            )

            guard fullHistoryReady else {
                continue
            }

            guard targetExists else {
                continue
            }

            activeJumpScrollRequest = request
            onJumpScrollStarted(request)

            scheduleMeasuredScroll(
                to: request.itemID,
                centered: true,
                using: scrollProxy,
                completion: { succeeded in
                    finishJumpScroll(request, succeeded: succeeded)
                }
            )

            return
        }

        onJumpScrollCompleted(request, false)
    }

    private func finishJumpScroll(
        _ request: HistoryViewModel.JumpToHistoryRequest,
        succeeded: Bool
    ) {
        guard activeJumpScrollRequest == request else {
            return
        }

        activeJumpScrollRequest = nil
        onJumpScrollCompleted(request, succeeded)
    }

    private func scheduleMeasuredScroll(
        to itemID: UUID,
        centered: Bool,
        using scrollProxy: ScrollViewProxy,
        completion: ((Bool) -> Void)? = nil
    ) {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        cancelPendingMeasuredScroll()

        measuredTargetFrame = nil
        pendingMeasuredScrollTarget = PendingMeasuredScrollTarget(
            itemID: itemID,
            centered: centered,
            requestID: requestID
        )
        pendingMeasuredScrollCompletion = completion

        measuredScrollTask = Task { @MainActor in
            let attemptCount = centered ? 16 : 5
            let anchor: UnitPoint = centered ? .center : UnitPoint(x: 0.5, y: 0.5)

            for attempt in 0..<attemptCount {
                guard !Task.isCancelled else {
                    return
                }

                guard requestID == scrollRequestID else {
                    finishMeasuredScroll(requestID: requestID, succeeded: false)
                    return
                }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                guard !Task.isCancelled else {
                    return
                }

                guard itemExists(itemID) else {
                    continue
                }

                scrollController.syncMetricsImmediately()

                if centered, attempt < 3 {
                    scrollToEstimatedPosition(
                        itemID: itemID,
                        centered: centered
                    )
                }

                let shouldUseProxyScroll: Bool
                if centered {
                    shouldUseProxyScroll = measuredTargetFrame == nil || attempt < 4
                } else {
                    shouldUseProxyScroll = measuredTargetFrame == nil && attempt >= 2
                }

                if shouldUseProxyScroll {
                    withAnimation(nil) {
                        scrollProxy.scrollTo(scrollID(forItemID: itemID), anchor: anchor)
                    }
                }

                await Task.yield()
                try? await Task.sleep(nanoseconds: 14_000_000)

                guard !Task.isCancelled else {
                    return
                }

                if performExactMeasuredScroll(to: itemID, centered: centered) {
                    logScrollDiagnostics("Measured scroll succeeded for \(itemID.uuidString)")
                    finishMeasuredScroll(requestID: requestID, succeeded: true)
                    return
                }
            }

            logScrollDiagnostics("Measured scroll failed for \(itemID.uuidString)")
            finishMeasuredScroll(requestID: requestID, succeeded: false)
        }
    }

    private func finishMeasuredScroll(requestID: UInt, succeeded: Bool) {
        guard pendingMeasuredScrollTarget?.requestID == requestID else {
            return
        }

        pendingMeasuredScrollTarget = nil
        measuredTargetFrame = nil
        measuredScrollTask = nil

        let completion = pendingMeasuredScrollCompletion
        pendingMeasuredScrollCompletion = nil

        completion?(succeeded)
    }

    private func cancelPendingMeasuredScroll() {
        measuredScrollTask?.cancel()
        measuredScrollTask = nil

        pendingMeasuredScrollTarget = nil
        measuredTargetFrame = nil

        let completion = pendingMeasuredScrollCompletion
        pendingMeasuredScrollCompletion = nil

        completion?(false)
    }

    private func scheduleKeyboardNavigationScroll(to itemID: UUID) {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        cancelPendingMeasuredScroll()
        cancelKeyboardNavigationScroll()

        keyboardNavigationScrollTask = Task { @MainActor in
            await Task.yield()

            guard !Task.isCancelled else {
                return
            }

            guard requestID == scrollRequestID else {
                return
            }

            performKeyboardNavigationScroll(to: itemID)
            keyboardNavigationScrollTask = nil
        }
    }

    private func cancelKeyboardNavigationScroll() {
        keyboardNavigationScrollTask?.cancel()
        keyboardNavigationScrollTask = nil
    }

    private func scheduleKeyboardNavigationCommit(for request: HistoryViewModel.KeyboardNavigationRequest) {
        cancelKeyboardNavigationCommit()
        let requestTimestamp = Date.timeIntervalSinceReferenceDate
        let shouldPreferImmediateScroll =
            requestTimestamp - lastKeyboardNavigationRequestTimestamp < Self.rapidKeyboardNavigationThreshold
        lastKeyboardNavigationRequestTimestamp = requestTimestamp

        keyboardNavigationCommitTask = Task { @MainActor in
            let didAnimateScroll = await performAnimatedKeyboardNavigationScrollIfNeeded(
                to: request.itemID,
                preferImmediateScroll: shouldPreferImmediateScroll
            )

            guard !Task.isCancelled else {
                return
            }

            if didAnimateScroll {
                try? await Task.sleep(nanoseconds: 30_000_000)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else {
                return
            }

            onCompleteKeyboardNavigation(request)
            keyboardNavigationCommitTask = nil
        }
    }

    private func cancelKeyboardNavigationCommit() {
        keyboardNavigationCommitTask?.cancel()
        keyboardNavigationCommitTask = nil
    }

    private func prewarmAssetsForKeyboardNavigation(request: HistoryViewModel.KeyboardNavigationRequest) {
        keyboardAssetPrewarmTask?.cancel()

        let startIndex = max(0, request.targetIndex - 8)
        let endIndex = min(items.count, request.targetIndex + 9)
        let nearbyItems = Array(items[startIndex..<endIndex])

        keyboardAssetPrewarmTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmSourceIcons(
                for: nearbyItems,
                settings: settings,
                limit: 20
            )
        }
    }

    private func scrollToEstimatedPosition(itemID: UUID, centered: Bool) {
        let rows = listCache.matches(items: items)
            ? listCache.displayRows
            : ClipboardListStructure.displayRows(from: items)

        guard let estimatedMidY = ClipboardListStructure.estimatedMidY(
            forItemID: itemID,
            in: rows
        ) else {
            return
        }

        let viewportHeight = max(1, scrollController.viewportHeight)
        let targetY = centered ? viewportHeight / 2 : viewportHeight * 0.35
        let targetOffset = estimatedMidY - targetY

        logScrollDiagnostics(
            "Estimated jump scroll item=\(itemID.uuidString) targetOffset=\(targetOffset)"
        )

        scrollController.scrollTo(offset: targetOffset)
        scrollController.syncMetricsImmediately()
    }

    private func performKeyboardNavigationScroll(to itemID: UUID) {
        guard let navigationMetrics = keyboardNavigationMetrics(for: itemID) else {
            return
        }
        guard abs(navigationMetrics.targetOffset - navigationMetrics.currentOffset) > 0.5 else {
            return
        }

        scrollController.scrollTo(offset: navigationMetrics.targetOffset)
        scrollController.syncMetricsImmediately()
    }

    private func performAnimatedKeyboardNavigationScrollIfNeeded(
        to itemID: UUID,
        preferImmediateScroll: Bool
    ) async -> Bool {
        guard let navigationMetrics = keyboardNavigationMetrics(for: itemID) else {
            return false
        }
        guard abs(navigationMetrics.targetOffset - navigationMetrics.currentOffset) > 0.5 else {
            return false
        }

        if preferImmediateScroll {
            scrollController.scrollTo(offset: navigationMetrics.targetOffset)
            scrollController.syncMetricsImmediately()
            return true
        }

        let duration = 0.08
        let frameCount = 6

        for step in 1...frameCount {
            guard !Task.isCancelled else {
                return false
            }

            let progress = CGFloat(step) / CGFloat(frameCount)
            let easedProgress = 1 - pow(1 - progress, 3)
            let offset = navigationMetrics.currentOffset
                + (navigationMetrics.targetOffset - navigationMetrics.currentOffset) * easedProgress

            scrollController.scrollTo(offset: offset)

            if step < frameCount {
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(frameCount)) * 1_000_000_000))
            }
        }

        scrollController.syncMetricsImmediately()
        return true
    }

    private func keyboardNavigationMetrics(
        for itemID: UUID
    ) -> (currentOffset: CGFloat, targetOffset: CGFloat)? {
        let rows = listCache.matches(items: items)
            ? listCache.displayRows
            : ClipboardListStructure.displayRows(from: items)

        guard let estimatedFrame = ClipboardListStructure.estimatedFrame(
            forItemID: itemID,
            in: rows
        ) else {
            return nil
        }

        scrollController.syncMetricsImmediately()

        let viewportHeight = max(1, scrollController.viewportHeight)
        let currentOffset = scrollController.scrollOffset
        let maxOffset = max(0, scrollController.contentHeight - viewportHeight)
        let edgePadding = Self.keyboardNavigationComfortPadding
        let visibleMinY = currentOffset + edgePadding
        let visibleMaxY = currentOffset + viewportHeight - edgePadding

        let rawTargetOffset: CGFloat?
        if estimatedFrame.minY < visibleMinY {
            rawTargetOffset = estimatedFrame.minY - edgePadding
        } else if estimatedFrame.maxY > visibleMaxY {
            rawTargetOffset = estimatedFrame.maxY - viewportHeight + edgePadding
        } else {
            rawTargetOffset = nil
        }

        guard let rawTargetOffset else {
            return nil
        }

        return (
            currentOffset: currentOffset,
            targetOffset: resolvedKeyboardNavigationTargetOffset(
                rawTargetOffset: rawTargetOffset,
                maxOffset: maxOffset
            )
        )
    }

    private func resolvedKeyboardNavigationTargetOffset(rawTargetOffset: CGFloat, maxOffset: CGFloat) -> CGFloat {
        let clampedTargetOffset = rawTargetOffset.clamped(to: 0...maxOffset)

        if clampedTargetOffset <= Self.keyboardNavigationTopSnapThreshold {
            return 0
        }

        return clampedTargetOffset
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

        let clampedTargetOffset = targetOffset.clamped(to: 0...max(0, maxOffset))

        guard abs(scrollController.scrollOffset - clampedTargetOffset) > 1 else {
            return true
        }

        scrollController.scrollTo(offset: clampedTargetOffset)
        scrollController.syncMetricsImmediately()

        return abs(scrollController.scrollOffset - clampedTargetOffset) <= 2
    }

    private func scheduleOpenScrollToTop() {
        scrollController.scrollToTopImmediately()
        scrollController.syncMetricsImmediately()
        isAwaitingInitialOpenScroll = false
        scheduleScrollToTop()
    }

    private func scheduleScrollToTop() {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        cancelPendingMeasuredScroll()
        cancelKeyboardNavigationScroll()

        Task { @MainActor in
            for attempt in 0..<12 {
                guard requestID == scrollRequestID else { return }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                scrollController.scrollToTopImmediately()
                scrollController.syncMetricsImmediately()
            }
        }
    }

    private func scheduleScrollToBottom() {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        cancelPendingMeasuredScroll()
        cancelKeyboardNavigationScroll()

        Task { @MainActor in
            for attempt in 0..<12 {
                guard requestID == scrollRequestID else { return }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                scrollController.scrollToBottomImmediately()
                scrollController.syncMetricsImmediately()
            }
        }
    }

    private func scheduleOpenRestoreOffset(_ offset: CGFloat) {
        scrollRequestID &+= 1
        let requestID = scrollRequestID

        cancelPendingMeasuredScroll()
        cancelKeyboardNavigationScroll()

        scrollController.scrollTo(offset: offset)
        scrollController.syncMetricsImmediately()
        isAwaitingInitialOpenScroll = false

        Task { @MainActor in
            for attempt in 0..<12 {
                guard requestID == scrollRequestID else { return }

                if attempt == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: 35_000_000)
                }

                scrollController.scrollTo(offset: offset)
                scrollController.syncMetricsImmediately()
            }
        }
    }

    private func restoreScrollOffsetForReopen(_ offset: CGFloat) {
        isAwaitingInitialOpenScroll = offset > 1
        scheduleOpenRestoreOffset(offset)
    }

    private func selectFirstItemAndScrollToTop(using scrollProxy: ScrollViewProxy) {
        contextMenuHighlightedItemID = nil
        hoveredItemID = nil

        guard let preferredTopItemID = onSelectPreferredTopItem() else {
            scheduleOpenScrollToTop()
            return
        }

        if items.first?.id == preferredTopItemID {
            scheduleOpenScrollToTop()
        } else {
            scheduleMeasuredScroll(
                to: preferredTopItemID,
                centered: false,
                using: scrollProxy
            )
        }
    }

    private func applyOpenScrollRequest(
        _ request: HistoryViewModel.OpenListScrollRequest,
        using scrollProxy: ScrollViewProxy
    ) {
        isAwaitingInitialOpenScroll = shouldHideDuringInitialOpenScroll(for: request)

        switch request.mode {
        case .scrollToTop:
            scheduleOpenScrollToTop()

        case .scrollToItem(let itemID):
            scheduleMeasuredScroll(
                to: itemID,
                centered: true,
                using: scrollProxy
            )
        }
    }

    private func applyOpenScrollRequestIfNeeded(using scrollProxy: ScrollViewProxy) {
        guard openScrollRequestToken != lastAppliedOpenScrollRequestToken else {
            return
        }

        lastAppliedOpenScrollRequestToken = openScrollRequestToken

        guard let openScrollRequest else {
            return
        }

        applyOpenScrollRequest(openScrollRequest, using: scrollProxy)
    }

    private func rebuildListCache() {
        listCache = ClipboardListStructure.makeDisplayCache(from: items)
    }

    private func prewarmVisibleAssets() {
        assetPrewarmTask?.cancel()

        let prewarmItems = Array(items.prefix(160))

        assetPrewarmTask = Task { @MainActor in
            await ClipboardItemRowAssetLoader.prewarmSourceIcons(
                for: prewarmItems,
                settings: settings,
                limit: 72
            )
        }
    }

    private func scrollID(forItemID itemID: UUID) -> String {
        "item-\(itemID.uuidString)"
    }

    private func primaryLabelText(for item: ClipboardItem) -> String {
        listCache.primaryLabelText(for: item)
    }

    private func shouldHideDuringInitialOpenScroll(
        for request: HistoryViewModel.OpenListScrollRequest?
    ) -> Bool {
        guard let request else {
            return false
        }

        switch request.mode {
        case .scrollToTop:
            return scrollController.scrollOffset > 1

        case .scrollToItem:
            return false
        }
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

    private func logScrollDiagnostics(_ message: @autoclosure () -> String) {
#if DEBUG
        let resolvedMessage = message()
        BufferLogger.ui.debug("\(resolvedMessage, privacy: .public)")
#endif
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
