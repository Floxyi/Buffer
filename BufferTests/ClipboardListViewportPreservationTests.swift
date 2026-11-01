import AppKit
import SwiftUI
import XCTest

@testable import Buffer

@MainActor
final class ClipboardListViewportPreservationTests: XCTestCase {
    func testRemovalAboveViewportPreservesSurvivingAnchorPosition() throws {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let nextSnapshot = makeSnapshot(items: items.filter { $0.id != items[3].id })
        let previousFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: items[20].id)
        )
        let nextFrame = try XCTUnwrap(
            nextSnapshot.displayCache.layoutIndex.frame(for: items[20].id)
        )
        let currentOffset = previousFrame.minY + 12

        let targetOffset = try XCTUnwrap(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: nextSnapshot,
                currentScrollOffset: currentOffset,
                viewportHeight: 320
            )
        )

        XCTAssertEqual(
            nextFrame.minY - targetOffset,
            previousFrame.minY - currentOffset,
            accuracy: 0.001
        )
    }

    func testRemovingVisibleRowKeepsOffsetWhenPrecedingAnchorSurvives() throws {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let removedFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: items[20].id)
        )
        let nextSnapshot = makeSnapshot(items: items.filter { $0.id != items[20].id })

        let targetOffset = try XCTUnwrap(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: nextSnapshot,
                currentScrollOffset: removedFrame.minY,
                viewportHeight: 320
            )
        )

        XCTAssertEqual(targetOffset, removedFrame.minY, accuracy: 0.001)
    }

    func testRemovingWholeSectionAboveViewportPreservesSurvivingAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let newest = (0..<8).map { index in
            ClipboardItem(
                type: .text,
                timestamp: referenceDate.addingTimeInterval(-TimeInterval(index * 60)),
                textContent: "new-\(index)"
            )
        }
        let onlyOlderItem = ClipboardItem(
            type: .text,
            timestamp: referenceDate.addingTimeInterval(-86_400),
            textContent: "old-section"
        )
        let oldest = (0..<16).map { index in
            ClipboardItem(
                type: .text,
                timestamp: referenceDate.addingTimeInterval(-172_800 - TimeInterval(index * 60)),
                textContent: "oldest-\(index)"
            )
        }
        let items = newest + [onlyOlderItem] + oldest
        let previousSnapshot = makeSnapshot(
            items: items,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let nextSnapshot = makeSnapshot(
            items: items.filter { $0.id != onlyOlderItem.id },
            referenceDate: referenceDate,
            calendar: calendar
        )
        let anchor = oldest[8]
        let previousFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: anchor.id)
        )
        let nextFrame = try XCTUnwrap(nextSnapshot.displayCache.layoutIndex.frame(for: anchor.id))
        let currentOffset = previousFrame.minY + 7

        let targetOffset = try XCTUnwrap(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: nextSnapshot,
                currentScrollOffset: currentOffset,
                viewportHeight: 320
            )
        )

        XCTAssertEqual(
            nextFrame.minY - targetOffset,
            previousFrame.minY - currentOffset,
            accuracy: 0.001
        )
    }

    func testRemovingVisibleBlockUsesNearestSurvivingAnchor() throws {
        let items = (0..<80).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let currentOffset = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: items[40].id)
        ).minY
        let removedIDs = Set(items[30...45].map(\.id))
        let nextSnapshot = makeSnapshot(items: items.filter { !removedIDs.contains($0.id) })
        let followingItem = items[46]
        let previousFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: followingItem.id)
        )
        let nextFrame = try XCTUnwrap(
            nextSnapshot.displayCache.layoutIndex.frame(for: followingItem.id)
        )

        let targetOffset = try XCTUnwrap(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: nextSnapshot,
                currentScrollOffset: currentOffset,
                viewportHeight: 320
            )
        )

        XCTAssertEqual(
            nextFrame.minY - targetOffset,
            previousFrame.minY - currentOffset,
            accuracy: 0.001
        )
    }

    func testQueryChangeAndReorderingDoNotCreateRemovalTarget() {
        let items = (0..<8).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let querySnapshot = makeSnapshot(
            items: Array(items.dropFirst()),
            query: ClipboardQuery(text: "item")
        )
        let reorderedSnapshot = makeSnapshot(
            items: [items[1], items[0]] + Array(items.dropFirst(2))
        )

        XCTAssertNil(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: querySnapshot,
                currentScrollOffset: 200,
                viewportHeight: 320
            )
        )
        XCTAssertNil(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: reorderedSnapshot,
                currentScrollOffset: 200,
                viewportHeight: 320
            )
        )
    }

    func testConcurrentInsertionDoesNotMaskRemovalPreservation() throws {
        let items = (0..<30).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let anchor = items[20]
        let previousFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: anchor.id)
        )
        let insertedItem = ClipboardItem.text("new-item")
        let nextItems = [insertedItem] + items.filter { $0.id != items[3].id }
        let nextSnapshot = makeSnapshot(items: nextItems)
        let nextFrame = try XCTUnwrap(
            nextSnapshot.displayCache.layoutIndex.frame(for: anchor.id)
        )
        let currentOffset = previousFrame.minY + 12

        let targetOffset = try XCTUnwrap(
            ClipboardListViewportPreservationResolver.targetOffset(
                from: previousSnapshot,
                to: nextSnapshot,
                currentScrollOffset: currentOffset,
                viewportHeight: 320
            )
        )

        XCTAssertEqual(
            nextFrame.minY - targetOffset,
            previousFrame.minY - currentOffset,
            accuracy: 0.001
        )
    }

    func testViewportUpdateOwnsOffsetUntilReleased() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)

        controller.scrollTo(offset: 200)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 900))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        controller.beginViewportUpdate(at: 900)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 900, accuracy: 0.001)
        controller.cancelViewportUpdate()
    }

    func testViewportUpdateRejectsCompetingProgrammaticScroll() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)

        controller.scrollTo(offset: 800)
        controller.beginViewportUpdate(at: 800)
        controller.scrollTo(offset: 0)

        XCTAssertEqual(scrollView.contentView.bounds.minY, 800, accuracy: 0.001)

        controller.completeViewportUpdate(at: 740)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 740, accuracy: 0.001)
    }

    func testViewportUpdateRestoresNativeBoundsChangeBeforeDisplay() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)

        controller.scrollTo(offset: 800)
        controller.beginViewportUpdate(at: 800)

        // This models the clip-view clamp AppKit can perform while SwiftUI
        // replaces the list's document geometry.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(scrollView.contentView.bounds.minY, 800, accuracy: 0.001)
        controller.cancelViewportUpdate()
    }

    func testNativeUserScrollPublishesInteractionExactlyOnce() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        var userScrollStartCount = 0
        controller.onUserScrollStarted = {
            userScrollStartCount += 1
        }

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 900))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertEqual(userScrollStartCount, 1)
        XCTAssertEqual(scrollView.contentView.bounds.minY, 900, accuracy: 0.001)
    }

    func testNativeUserScrollReleasesActiveViewportLock() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        controller.scrollTo(offset: 800)
        controller.beginViewportUpdate(at: 800)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 752))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(scrollView.contentView.bounds.minY, 752, accuracy: 0.001)
    }

    func testUnrelatedContentUpdateDoesNotMoveViewport() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 2_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        let preserver = ClipboardListViewportPreserver()
        let items = (0..<8).map { ClipboardItem.text("item-\($0)") }
        let nextSnapshot = makeSnapshot(items: items, query: ClipboardQuery(text: "item"))

        controller.scrollTo(offset: 700)
        preserver.contentDidChange(
            to: nextSnapshot,
            scrollController: controller
        )

        XCTAssertEqual(scrollView.contentView.bounds.minY, 700, accuracy: 0.001)
    }

    func testRemovalTransitionBridgesDocumentGeometryUntilTargetOffsetIsInstalled() throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 4_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        let preserver = ClipboardListViewportPreserver()
        let items = (0..<40).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let nextSnapshot = makeSnapshot(items: items.filter { $0.id != items[3].id })
        let anchor = items[24]
        let previousFrame = try XCTUnwrap(
            previousSnapshot.displayCache.layoutIndex.frame(for: anchor.id)
        )
        let nextFrame = try XCTUnwrap(
            nextSnapshot.displayCache.layoutIndex.frame(for: anchor.id)
        )
        let initialOffset = previousFrame.minY + 9
        controller.scrollTo(offset: initialOffset)

        preserver.prepareForRemoval(
            [items[3].id],
            from: previousSnapshot,
            scrollController: controller
        )
        let transition = preserver.transition(for: nextSnapshot)
        let expectedTarget = nextFrame.minY - (previousFrame.minY - initialOffset)

        XCTAssertEqual(
            transition.contentOffset,
            initialOffset - expectedTarget,
            accuracy: 0.001
        )
        XCTAssertEqual(
            transition.minimumContentHeight,
            previousSnapshot.displayCache.layoutIndex.contentHeight,
            accuracy: 0.001
        )

        preserver.contentDidChange(to: nextSnapshot, scrollController: controller)

        XCTAssertEqual(scrollView.contentView.bounds.minY, expectedTarget, accuracy: 0.001)
        XCTAssertEqual(preserver.transition(for: nextSnapshot), .identity)
    }

    func testConsecutiveRemovalKeepsNewestViewportLockUntilItsOwnPublication() async throws {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 6_000))
        let controller = ScrollController()
        controller.configure(scrollView: scrollView, interactionMode: .system)
        let preserver = ClipboardListViewportPreserver()
        let items = (0..<80).map { ClipboardItem.text("item-\($0)") }
        let firstSnapshot = makeSnapshot(items: items)
        let secondItems = items.filter { $0.id != items[2].id }
        let secondSnapshot = makeSnapshot(items: secondItems)
        let thirdSnapshot = makeSnapshot(items: secondItems.filter { $0.id != items[3].id })

        controller.scrollTo(offset: 1_600)
        preserver.prepareForRemoval(
            [items[2].id],
            from: firstSnapshot,
            scrollController: controller
        )
        preserver.contentDidChange(to: secondSnapshot, scrollController: controller)

        let secondOffset = controller.currentScrollOffsetSnapshot()
        preserver.prepareForRemoval(
            [items[3].id],
            from: secondSnapshot,
            scrollController: controller
        )

        // The first mutation's release task would fire during this interval.
        try await Task.sleep(for: .milliseconds(140))
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertEqual(scrollView.contentView.bounds.minY, secondOffset, accuracy: 0.001)

        preserver.contentDidChange(to: thirdSnapshot, scrollController: controller)
        XCTAssertEqual(preserver.transition(for: thirdSnapshot), .identity)
    }

    func testRenderingWindowUsesBoundedRowsAndExactSpacerHeights() throws {
        let items = (0..<500).map { ClipboardItem.text("item-\($0)") }
        let snapshot = makeSnapshot(items: items)
        let layoutIndex = snapshot.displayCache.layoutIndex

        let window = layoutIndex.renderingWindow(
            scrollOffset: layoutIndex.contentHeight * 0.55,
            viewportHeight: 320,
            overscan: 200
        )

        XCTAssertFalse(window.range.isEmpty)
        XCTAssertLessThan(window.range.count, layoutIndex.rowEntries.count)

        let firstEntry = try XCTUnwrap(
            layoutIndex.rowEntries[safe: window.range.lowerBound]
        )
        let lastEntry = try XCTUnwrap(
            layoutIndex.rowEntries[safe: window.range.upperBound - 1]
        )
        let expectedLeadingHeight =
            firstEntry.frame.minY - ClipboardListStructure.LayoutMetrics.contentPadding
        let expectedTrailingHeight =
            layoutIndex.contentHeight
            - ClipboardListStructure.LayoutMetrics.contentPadding
            - lastEntry.frame.maxY

        XCTAssertEqual(window.leadingSpacerHeight, expectedLeadingHeight, accuracy: 0.001)
        XCTAssertEqual(window.trailingSpacerHeight, expectedTrailingHeight, accuracy: 0.001)
    }

    func testRenderingWindowStaysBoundedForMaximumHistory() {
        let items = (0..<10_000).map { ClipboardItem.text("item-\($0)") }
        let snapshot = makeSnapshot(items: items)

        let window = snapshot.displayCache.layoutIndex.renderingWindow(
            scrollOffset: snapshot.displayCache.layoutIndex.contentHeight * 0.73,
            viewportHeight: 420,
            overscan: 720
        )

        XCTAssertLessThan(window.range.count, 100)
        XCTAssertGreaterThan(window.leadingSpacerHeight, 0)
        XCTAssertGreaterThan(window.trailingSpacerHeight, 0)
    }

    func testRenderingWindowRetainsItsRowsAcrossSmallScrollChanges() {
        let items = (0..<500).map { ClipboardItem.text("item-\($0)") }
        let snapshot = makeSnapshot(items: items)
        let coordinator = ClipboardListRenderingWindowCoordinator()
        let initialOffset = snapshot.displayCache.layoutIndex.contentHeight * 0.5

        coordinator.update(
            snapshotID: snapshot.id,
            query: snapshot.query,
            layoutIndex: snapshot.displayCache.layoutIndex,
            scrollOffset: initialOffset,
            viewportHeight: 320,
            pinnedItemCount: 0
        )
        let initialWindow = coordinator.renderingWindow

        coordinator.update(
            snapshotID: snapshot.id,
            query: snapshot.query,
            layoutIndex: snapshot.displayCache.layoutIndex,
            scrollOffset: initialOffset + 80,
            viewportHeight: 320,
            pinnedItemCount: 0
        )

        XCTAssertEqual(coordinator.renderingWindow, initialWindow)
    }

    func testRenderingWindowRetainsItsRangeAcrossRemovalPublication() {
        let items = (0..<500).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let nextSnapshot = makeSnapshot(items: items.filter { $0.id != items[250].id })
        let coordinator = ClipboardListRenderingWindowCoordinator()
        let offset = previousSnapshot.displayCache.layoutIndex.contentHeight * 0.5

        coordinator.update(
            snapshotID: previousSnapshot.id,
            query: previousSnapshot.query,
            layoutIndex: previousSnapshot.displayCache.layoutIndex,
            scrollOffset: offset,
            viewportHeight: 320,
            pinnedItemCount: 0
        )
        let previousRange = coordinator.renderingWindow.range

        coordinator.update(
            snapshotID: nextSnapshot.id,
            query: nextSnapshot.query,
            layoutIndex: nextSnapshot.displayCache.layoutIndex,
            scrollOffset: offset,
            viewportHeight: 320,
            pinnedItemCount: 0
        )

        XCTAssertEqual(coordinator.renderingWindow.range, previousRange)
    }

    func testLateMetricsFromPreviousSnapshotCannotRestoreItsRenderingWindow() {
        let items = (0..<500).map { ClipboardItem.text("item-\($0)") }
        let previousSnapshot = makeSnapshot(items: items)
        let nextSnapshot = makeSnapshot(items: Array(items.dropFirst(120)))
        let coordinator = ClipboardListRenderingWindowCoordinator()
        let previousOffset = previousSnapshot.displayCache.layoutIndex.contentHeight * 0.75

        coordinator.update(
            snapshotID: previousSnapshot.id,
            query: previousSnapshot.query,
            layoutIndex: previousSnapshot.displayCache.layoutIndex,
            scrollOffset: previousOffset,
            viewportHeight: 320,
            pinnedItemCount: 0
        )

        let resolvedWindow = coordinator.resolvedWindow(
            snapshotID: nextSnapshot.id,
            query: nextSnapshot.query,
            layoutIndex: nextSnapshot.displayCache.layoutIndex,
            scrollOffset: 120,
            viewportHeight: 320,
            pinnedItemCount: 0
        )
        coordinator.update(
            snapshotID: previousSnapshot.id,
            query: previousSnapshot.query,
            layoutIndex: previousSnapshot.displayCache.layoutIndex,
            scrollOffset: previousOffset + 500,
            viewportHeight: 320,
            pinnedItemCount: 0
        )
        coordinator.update(
            snapshotID: nextSnapshot.id,
            query: nextSnapshot.query,
            layoutIndex: nextSnapshot.displayCache.layoutIndex,
            scrollOffset: 120,
            viewportHeight: 320,
            pinnedItemCount: 0
        )

        XCTAssertEqual(coordinator.renderingWindow, resolvedWindow)
    }

    func testProductionListPreservesViewportAcrossRepeatedVisibleDeletions() async throws {
        let harness = try await ClipboardViewportTestHarness.make(itemCount: 500)
        defer { harness.close() }

        let scrollProgresses: [CGFloat] = [
            0.08, 0.19, 0.34, 0.52, 0.71, 0.89, 0.27, 0.63,
        ]
        let deletionPositions: [CGFloat] = [0.08, 0.22, 0.48, 0.76]
        for iteration in 0..<24 {
            let scrollProgress = scrollProgresses[iteration % scrollProgresses.count]
            try await harness.deleteVisibleItem(
                scrollProgress: scrollProgress,
                minimumViewportFraction: deletionPositions[iteration % deletionPositions.count]
            )
        }
    }

    private func makeSnapshot(
        items: [ClipboardItem],
        query: ClipboardQuery = ClipboardQuery(),
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ClipboardListContentSnapshot {
        let snapshotID = UUID()
        return ClipboardListContentSnapshot(
            id: snapshotID,
            items: items,
            query: query,
            displayCache: ClipboardListStructure.makeDisplayCache(
                from: items,
                sourceSnapshotID: snapshotID,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }
}

@MainActor
private final class ClipboardViewportTestHarness {
    let viewModel: HistoryViewModel
    let hostingView: NSHostingView<AnyView>
    let window: NSWindow
    let scrollView: NSScrollView
    let scrollBridge: ClipboardViewportScrollBridge

    private init(
        viewModel: HistoryViewModel,
        hostingView: NSHostingView<AnyView>,
        window: NSWindow,
        scrollView: NSScrollView,
        scrollBridge: ClipboardViewportScrollBridge
    ) {
        self.viewModel = viewModel
        self.hostingView = hostingView
        self.window = window
        self.scrollView = scrollView
        self.scrollBridge = scrollBridge
    }

    static func make(itemCount: Int) async throws -> ClipboardViewportTestHarness {
        let settings = makeHistoryTestSettings()
        settings.setHistoryLimit(10_000)
        let store = makeHistoryTestStore(settings: settings)
        let referenceDate = Date()
        let items = (0..<itemCount).map { index in
            ClipboardItem(
                type: .text,
                timestamp: referenceDate.addingTimeInterval(-TimeInterval(index * 21_600)),
                textContent: "item-\(index)",
                isPinned: index < 3,
                pinnedAt: index < 3 ? referenceDate.addingTimeInterval(TimeInterval(index)) : nil
            )
        }
        await populateStore(store, with: items)

        let assetProvider = ClipboardViewportAssetProvider()
        let keyboardScrollRouter = HistoryKeyboardScrollRouter()
        let scrollBridge = ClipboardViewportScrollBridge()
        let viewModel = HistoryViewModel(
            store: store,
            settingsManager: settings,
            ocrService: FakeOCRService(result: ""),
            assetProvider: assetProvider,
            keyboardScrollRouter: keyboardScrollRouter
        )
        await waitForHistorySearch(viewModel)

        let windowBox = ClipboardViewportWindowBox()
        let viewportProbe = ClipboardListViewportProbe()
        let hostingView = NSHostingView(
            rootView: AnyView(
                HistoryContentView(
                    viewModel: viewModel,
                    settings: settings,
                    pasteState: HistoryPasteStateController(),
                    contentReader: store,
                    itemAssetProvider: assetProvider,
                    listAssetPrewarmer: ClipboardListAssetPrewarmer(assetProvider: assetProvider),
                    keyboardScrollRouter: keyboardScrollRouter,
                    onCopy: { _ in false },
                    onPaste: { _ in },
                    presentingWindow: { windowBox.window },
                    onScrollOffsetProviderChanged: { scrollBridge.setProvider($0) },
                    onScrollOffsetRestorerChanged: { scrollBridge.restorer = $0 },
                    onDismiss: {},
                    onRestoreFocus: {},
                    paneSplitConfiguration: .ephemeral
                )
                .environment(\.clipboardListViewportProbe, viewportProbe)
            )
        )
        let frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        hostingView.frame = frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        windowBox.window = window
        window.orderFront(nil)

        await eventually {
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.viewportDescendants(of: NSScrollView.self).contains(where: {
                guard let documentView = $0.documentView else { return false }
                return documentView.frame.height > $0.contentView.bounds.height * 2
            })
        }
        let scrollView = try XCTUnwrap(
            hostingView.viewportDescendants(of: NSScrollView.self).first(where: {
                guard let documentView = $0.documentView else { return false }
                return documentView.frame.height > $0.contentView.bounds.height * 2
            })
        )
        return ClipboardViewportTestHarness(
            viewModel: viewModel,
            hostingView: hostingView,
            window: window,
            scrollView: scrollView,
            scrollBridge: scrollBridge
        )
    }

    func deleteVisibleItem(
        scrollProgress: CGFloat,
        minimumViewportFraction: CGFloat
    ) async throws {
        let provider = try XCTUnwrap(scrollBridge.provider)
        let maximumOffset = max(
            0,
            (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height
        )
        let requestedOffset = maximumOffset * scrollProgress
        await scrollAsUser(to: requestedOffset)
        await waitForStableViewport(at: requestedOffset, provider: provider)
        for _ in 0..<80 {
            self.hostingView.layoutSubtreeIfNeeded()
            if self.visibleTrackedRows().count >= 4 { break }
            await Task.yield()
        }

        var visibleRows = visibleTrackedRows()
        XCTAssertGreaterThanOrEqual(
            visibleRows.count,
            4,
            "Expected at least four materialized rows at the requested viewport"
        )
        let leadingRow = try XCTUnwrap(
            visibleRows.first(where: { $0.frame.minY >= 0 }) ?? visibleRows.first
        )
        var deletedRow = try XCTUnwrap(
            visibleRows.first(where: {
                $0.itemID != leadingRow.itemID
                    && $0.frame.minY
                        >= scrollView.contentView.bounds.height * minimumViewportFraction
            }) ?? visibleRows.last(where: { $0.itemID != leadingRow.itemID })
        )
        let deletedItem = try XCTUnwrap(
            viewModel.filteredItems.first(where: { $0.id == deletedRow.itemID })
        )
        viewModel.selectSingle(deletedItem.id)
        for _ in 0..<16 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
        visibleRows = visibleTrackedRows()
        deletedRow = try XCTUnwrap(
            visibleRows.first(where: { $0.itemID == deletedItem.id }),
            "The selected row must remain materialized before deletion"
        )
        let preservedOffsets = Dictionary(
            uniqueKeysWithValues:
                visibleRows
                .filter { $0.itemID != deletedRow.itemID && $0.frame.minY < deletedRow.frame.minY }
                .map { ($0.itemID, $0.frame.minY) }
        )
        XCTAssertFalse(preservedOffsets.isEmpty)
        performDeleteKeyboardCommand()
        var observedDrifts: [CGFloat] = []
        var sawFrameWithoutAnyPreservedRow = false
        await eventually {
            self.hostingView.layoutSubtreeIfNeeded()
            let visiblePreservedRows = preservedOffsets.compactMap { itemID, offset in
                self.trackedFrame(for: itemID).map { frame in
                    (frame: frame, expectedOffset: offset)
                }
            }
            if visiblePreservedRows.isEmpty {
                sawFrameWithoutAnyPreservedRow = true
            } else {
                observedDrifts.append(
                    contentsOf: visiblePreservedRows.map {
                        abs($0.frame.minY - $0.expectedOffset)
                    }
                )
            }
            return !self.viewModel.isSearching
                && !self.viewModel.filteredItems.contains(where: { $0.id == deletedItem.id })
                && visiblePreservedRows.contains {
                    abs($0.frame.minY - $0.expectedOffset) < 1
                }
        }

        // Keep sampling after the authoritative snapshot has arrived. Delayed
        // metrics callbacks and rendering-window reconciliation run on later
        // turns and previously could reintroduce a one-frame jump after an
        // apparently stable deletion.
        for _ in 0..<20 {
            hostingView.layoutSubtreeIfNeeded()
            let visiblePreservedRows = preservedOffsets.compactMap { itemID, offset in
                trackedFrame(for: itemID).map { frame in
                    (frame: frame, expectedOffset: offset)
                }
            }
            if visiblePreservedRows.isEmpty {
                sawFrameWithoutAnyPreservedRow = true
            } else {
                observedDrifts.append(
                    contentsOf: visiblePreservedRows.map {
                        abs($0.frame.minY - $0.expectedOffset)
                    }
                )
            }
            try? await Task.sleep(for: .milliseconds(8))
        }

        XCTAssertFalse(
            sawFrameWithoutAnyPreservedRow,
            "All rows above the deletion disappeared during the update; "
                + "offset=\(provider()), documentHeight=\(scrollView.documentView?.frame.height ?? -1), "
                + "preserved=\(preservedOffsets.mapValues { offset in offset }), "
                + "preservedIndices=\(preservedOffsets.keys.map { id in viewModel.filteredItems.firstIndex(where: { $0.id == id }) as Any }), "
                + "visibleRows=\(visibleTrackedRows().map { row in (viewModel.filteredItems.firstIndex(where: { $0.id == row.itemID }) as Any, row.frame.minY) })"
        )
        XCTAssertTrue(
            observedDrifts.allSatisfy { $0 < 1 },
            "Rows above the deletion flickered; observed pixel drifts: \(observedDrifts), "
                + "scroll offset: \(provider())"
        )
    }

    private func performDeleteKeyboardCommand() {
        let handler = HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: false,
            confirmDeleteWithKeyboardShortcut: false,
            actions: .init(
                handleModifierFlagsChange: { _ in },
                moveUp: { _ in },
                moveDown: { _ in },
                moveToFirst: { _ in },
                moveToLast: { _ in },
                commitSelection: {},
                dismiss: {},
                selectAll: {},
                makeDeleteRequest: viewModel.makeDeleteSelectionRequest,
                deleteSelection: viewModel.delete,
                copySelection: {},
                toggleBookmark: {},
                togglePinned: {},
                saveImage: {},
                quickPaste: { _ in },
                presentDeleteConfirmation: { _ in }
            )
        )
        handler.handle(.deleteSelection)
    }

    private func scrollAsUser(to targetOffset: CGFloat) async {
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        var currentOffset = scrollView.contentView.bounds.minY
        while abs(targetOffset - currentOffset) > 0.5 {
            let delta = (targetOffset - currentOffset).clamped(to: -320...320)
            let proposedBounds = NSRect(
                x: scrollView.contentView.bounds.minX,
                y: currentOffset + delta,
                width: scrollView.contentView.bounds.width,
                height: scrollView.contentView.bounds.height
            )
            let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)
            scrollView.contentView.scroll(to: constrainedBounds.origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()

            let nextOffset = scrollView.contentView.bounds.minY
            guard abs(nextOffset - currentOffset) > 0.5 else { break }
            currentOffset = nextOffset
        }
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
    }

    private func visibleTrackedRows() -> [(itemID: UUID, frame: CGRect)] {
        let viewportHeight = scrollView.contentView.bounds.height
        return
            hostingView
            .viewportDescendants(of: ClipboardListViewportTrackingView.self)
            .compactMap { view -> (itemID: UUID, frame: CGRect)? in
                guard let frame = view.frameInViewport(),
                    frame.maxY > 0,
                    frame.minY < viewportHeight
                else { return nil }
                return (view.itemID, frame)
            }
            .sorted { lhs, rhs in
                if lhs.frame.minY != rhs.frame.minY {
                    return lhs.frame.minY < rhs.frame.minY
                }
                return lhs.itemID.uuidString < rhs.itemID.uuidString
            }
    }

    private func trackedFrame(for itemID: UUID) -> CGRect? {
        hostingView
            .viewportDescendants(of: ClipboardListViewportTrackingView.self)
            .first(where: { $0.itemID == itemID })?
            .frameInViewport()
    }

    private func waitForStableViewport(
        at expectedOffset: CGFloat,
        provider: () -> CGFloat
    ) async {
        var consecutiveStableLayouts = 0
        for _ in 0..<80 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()

            if abs(provider() - expectedOffset) < 1 {
                consecutiveStableLayouts += 1
                if consecutiveStableLayouts == 16 {
                    return
                }
            } else {
                consecutiveStableLayouts = 0
            }
        }

        XCTFail(
            "The test viewport did not settle at \(expectedOffset); actual offset is \(provider())"
        )
    }

    func close() {
        hostingView.removeFromSuperview()
        window.contentView = nil
    }
}

@MainActor
private final class ClipboardViewportAssetProvider: ClipboardItemAssetProviding {
    func cachedThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) -> NSImage? { nil }
    func loadThumbnail(for item: ClipboardItem, leadingVisualSize: CGFloat) async -> NSImage? { nil }
    func cachedImageDimensionsText(for item: ClipboardItem) -> String? { nil }
    func loadImageDimensionsText(for item: ClipboardItem) async -> String? { nil }
    func cachedPreviewImage(for item: ClipboardItem) -> NSImage? { nil }
    func loadPreviewImage(for item: ClipboardItem) async -> NSImage? { nil }
    func loadFullText(for item: ClipboardItem) async -> String? { nil }
    func loadTextChunk(for item: ClipboardItem, charCount: Int) async -> ClipboardTextChunk? { nil }
    func loadItemSize(for item: ClipboardItem) async -> Int? { nil }
    func cachedLeadingIcon(for item: ClipboardItem) -> NSImage? { nil }
    func loadApplicationIcon(for item: ClipboardItem) async -> NSImage? { nil }
    func loadPreferredLeadingIcon(for item: ClipboardItem) async -> NSImage? { nil }
    func prewarmImageAssets(
        for items: [ClipboardItem],
        leadingVisualSize: CGFloat,
        limit: Int
    ) async {}
}

@MainActor
private final class ClipboardViewportScrollBridge {
    var provider: (() -> CGFloat)?
    var restorer: ((CGFloat) -> Void)?

    func setProvider(_ provider: (() -> CGFloat)?) {
        self.provider = provider
    }
}

@MainActor
private final class ClipboardViewportWindowBox {
    weak var window: NSWindow?
}

extension NSView {
    fileprivate func viewportDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        var matches: [ViewType] = []
        if let matchingView = self as? ViewType {
            matches.append(matchingView)
        }
        for subview in subviews {
            matches.append(contentsOf: subview.viewportDescendants(of: type))
        }
        return matches
    }
}
