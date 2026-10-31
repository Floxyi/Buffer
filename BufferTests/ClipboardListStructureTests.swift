import XCTest

@testable import Buffer

final class ClipboardListStructureTests: XCTestCase {
    func testLayoutIndexMatchesLegacyGeometry() throws {
        let items = (0..<40).map { ClipboardItem.text("item-\($0)") }
        let cache = ClipboardListStructure.makeDisplayCache(from: items)

        XCTAssertEqual(
            cache.layoutIndex.contentHeight,
            ClipboardListStructure.estimatedContentHeight(for: cache.displayRows),
            accuracy: 0.001
        )

        for item in items {
            let indexedFrame = try XCTUnwrap(cache.layoutIndex.frame(for: item.id))
            let legacyFrame = try XCTUnwrap(
                ClipboardListStructure.estimatedFrame(forItemID: item.id, in: cache.displayRows)
            )
            XCTAssertEqual(indexedFrame.minY, legacyFrame.minY, accuracy: 0.001)
            XCTAssertEqual(indexedFrame.height, legacyFrame.height, accuracy: 0.001)
        }
    }

    func testLayoutIndexFindsDeepViewportWithoutIncludingPrecedingItems() throws {
        let items = (0..<10_000).map { ClipboardItem.text("item-\($0)") }
        let cache = ClipboardListStructure.makeDisplayCache(from: items)
        let targetFrame = try XCTUnwrap(cache.layoutIndex.frame(for: items[9_500].id))

        let visible = cache.layoutIndex.visibleItemEntries(
            scrollOffset: targetFrame.minY,
            viewportHeight: 220
        )

        XCTAssertEqual(visible.first?.id, items[9_500].id)
        XCTAssertLessThanOrEqual(visible.count, 7)
        XCTAssertTrue(visible.allSatisfy { $0.itemIndex >= 9_500 })
    }

    func testLayoutIndexPreservesDisplayOrderForPinnedItems() throws {
        let first = ClipboardItem.text("first")
        var pinned = ClipboardItem.text("pinned")
        pinned.isPinned = true
        let cache = ClipboardListStructure.makeDisplayCache(from: [first, pinned])

        let firstVisible = try XCTUnwrap(
            cache.layoutIndex.visibleItemEntries(scrollOffset: 0, viewportHeight: 200).first
        )
        XCTAssertEqual(firstVisible.id, pinned.id)
        XCTAssertEqual(firstVisible.itemIndex, 1)
        XCTAssertEqual(cache.pinnedItemIDs, [pinned.id])
    }

    func testRebuildsCacheWhenWeekBoundaryChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let mondayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 18,
            hour: 9
        ).date!
        let sundayReferenceDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 17,
            hour: 9
        ).date!
        let lastTuesdayItemDate = DateComponents(
            calendar: calendar,
            year: 2026,
            month: 5,
            day: 12,
            hour: 12
        ).date!

        let items = [
            ClipboardItem(
                type: .text,
                timestamp: lastTuesdayItemDate,
                textContent: "last week item"
            )
        ]

        let staleCache = ClipboardListStructure.makeDisplayCache(
            from: items,
            referenceDate: sundayReferenceDate,
            calendar: calendar
        )

        XCTAssertFalse(staleCache.matches(items: items, referenceDate: mondayReferenceDate, calendar: calendar))

        let refreshedRows = ClipboardListStructure.displayRows(
            from: items,
            referenceDate: mondayReferenceDate,
            calendar: calendar
        )
        let sectionTitle = refreshedRows.compactMap { row -> String? in
            guard case .header(let title, _) = row.kind else { return nil }
            return title
        }.first

        XCTAssertEqual(sectionTitle, "LAST WEEK")
    }
}

@MainActor
final class ClipboardPinnedReorderCoordinatorTests: XCTestCase {
    func testSelectedPinsDragAsOneGroupAndCancelRestoresOrder() {
        let ids = (0..<5).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)

        let payload = coordinator.beginDrag(
            itemID: ids[2],
            selectedItemIDs: [ids[2], ids[0]]
        )
        coordinator.preview(
            destination: .before(ids[4])
        )

        XCTAssertEqual(payload.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(coordinator.displayedItemIDs, ids)

        coordinator.cancelDrag()

        XCTAssertEqual(coordinator.displayedItemIDs, ids)
    }

    func testDraggingUnselectedPinDoesNotIncludeExistingSelection() {
        let ids = (0..<3).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)

        let payload = coordinator.beginDrag(
            itemID: ids[2],
            selectedItemIDs: [ids[0], ids[1]]
        )

        XCTAssertEqual(payload.map(\.id), [ids[2]])
    }

    func testPreviewRejectsNoOpBoundaryAndAcceptsRealMove() {
        let ids = (0..<3).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)
        _ = coordinator.beginDrag(itemID: ids[0], selectedItemIDs: [ids[0]])

        XCTAssertFalse(coordinator.preview(destination: .before(ids[1])))
        XCTAssertTrue(coordinator.preview(destination: .end))
    }

    func testExternalAuthoritativeChangeCancelsActiveDrag() {
        let ids = (0..<3).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)
        _ = coordinator.beginDrag(itemID: ids[0], selectedItemIDs: [ids[0]])
        coordinator.preview(destination: .end)
        let externallyChanged = [ids[1], ids[0], ids[2]]

        coordinator.synchronize(
            authoritativeItemIDs: externallyChanged,
            allowsReordering: true
        )

        XCTAssertEqual(coordinator.displayedItemIDs, externallyChanged)
    }

    func testAccessibilityMovesSelectedPinsAsAVisualGroup() {
        let ids = (0..<4).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)

        let moveUp = coordinator.accessibilityRequest(
            for: ids[1],
            direction: .up,
            selectedItemIDs: [ids[1], ids[2]]
        )
        let moveDown = coordinator.accessibilityRequest(
            for: ids[1],
            direction: .down,
            selectedItemIDs: [ids[1], ids[2]]
        )

        XCTAssertEqual(
            moveUp,
            ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[1], ids[2]],
                destination: .before(ids[0])
            )
        )
        XCTAssertEqual(
            moveDown,
            ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[1], ids[2]],
                destination: .end
            )
        )
    }

    func testSuccessfulDropUpdatesOptimisticallyAndRepositoryConfirmsIt() async {
        let ids = (0..<3).map { _ in UUID() }
        let expectedOrder = [ids[1], ids[2], ids[0]]
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)
        _ = coordinator.beginDrag(itemID: ids[0], selectedItemIDs: [ids[0]])

        coordinator.preview(destination: .end)
        coordinator.acceptDrop(destination: .end, animation: nil) { _ in true }
        await Task.yield()

        XCTAssertEqual(coordinator.displayedItemIDs, expectedOrder)
        coordinator.synchronize(authoritativeItemIDs: expectedOrder, allowsReordering: true)
        XCTAssertEqual(coordinator.displayedItemIDs, expectedOrder)
    }

    func testFailedCommitRestoresAuthoritativeOrder() async {
        let ids = (0..<3).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)
        _ = coordinator.beginDrag(itemID: ids[0], selectedItemIDs: [ids[0]])

        coordinator.preview(destination: .end)
        coordinator.acceptDrop(destination: .end, animation: nil) { _ in false }
        await Task.yield()

        XCTAssertEqual(coordinator.displayedItemIDs, ids)
    }

    func testDropCommitUsesStablePreviewDestination() async {
        let ids = (0..<3).map { _ in UUID() }
        let coordinator = ClipboardPinnedReorderCoordinator()
        coordinator.synchronize(authoritativeItemIDs: ids, allowsReordering: true)
        _ = coordinator.beginDrag(itemID: ids[0], selectedItemIDs: [ids[0]])
        coordinator.preview(destination: .end)
        var committedRequest: ClipboardPinnedReorderRequest?

        coordinator.acceptDrop(destination: .end, animation: nil) { request in
            committedRequest = request
            return true
        }
        await Task.yield()

        XCTAssertEqual(
            committedRequest,
            ClipboardPinnedReorderRequest(
                movingItemIDs: [ids[0]],
                destination: .end
            )
        )
        XCTAssertEqual(coordinator.displayedItemIDs, [ids[1], ids[2], ids[0]])
        coordinator.synchronize(
            authoritativeItemIDs: [ids[1], ids[2], ids[0]],
            allowsReordering: true
        )
        XCTAssertEqual(coordinator.displayedItemIDs, [ids[1], ids[2], ids[0]])
    }
}

final class ClipboardPinnedDropLayoutTests: XCTestCase {
    func testAdjacentRowsShareOneBoundaryAcrossTheirSpacing() throws {
        let firstID = UUID()
        let secondID = UUID()
        let layout = try XCTUnwrap(
            ClipboardPinnedDropLayout(
                rows: [
                    .init(itemID: firstID, frame: CGRect(x: 0, y: 0, width: 300, height: 44)),
                    .init(itemID: secondID, frame: CGRect(x: 0, y: 48, width: 300, height: 44)),
                ],
                isFlipped: true
            )
        )

        let targetFromUpperRow = try XCTUnwrap(layout.target(at: CGPoint(x: 150, y: 43)))
        let targetFromSpacing = try XCTUnwrap(layout.target(at: CGPoint(x: 150, y: 46)))
        let targetFromLowerRow = try XCTUnwrap(layout.target(at: CGPoint(x: 150, y: 49)))

        XCTAssertEqual(targetFromUpperRow.destination, .before(secondID))
        XCTAssertEqual(targetFromUpperRow, targetFromSpacing)
        XCTAssertEqual(targetFromSpacing, targetFromLowerRow)
        XCTAssertEqual(targetFromSpacing.indicatorFrame.midY, 46)
    }

    func testCanonicalBoundaryAlsoWorksInNonFlippedCoordinates() throws {
        let firstID = UUID()
        let secondID = UUID()
        let layout = try XCTUnwrap(
            ClipboardPinnedDropLayout(
                rows: [
                    .init(itemID: firstID, frame: CGRect(x: 0, y: 48, width: 300, height: 44)),
                    .init(itemID: secondID, frame: CGRect(x: 0, y: 0, width: 300, height: 44)),
                ],
                isFlipped: false
            )
        )

        let targetAboveSpacing = try XCTUnwrap(layout.target(at: CGPoint(x: 150, y: 47)))
        let targetBelowSpacing = try XCTUnwrap(layout.target(at: CGPoint(x: 150, y: 45)))

        XCTAssertEqual(targetAboveSpacing.destination, .before(secondID))
        XCTAssertEqual(targetAboveSpacing, targetBelowSpacing)
        XCTAssertEqual(targetAboveSpacing.indicatorFrame.midY, 46)
    }

    func testPointerOutsidePinnedRegionDoesNotProduceDropTarget() throws {
        let layout = try XCTUnwrap(
            ClipboardPinnedDropLayout(
                rows: [
                    .init(
                        itemID: UUID(),
                        frame: CGRect(x: 0, y: 0, width: 300, height: 44)
                    )
                ],
                isFlipped: true
            )
        )

        XCTAssertNil(layout.target(at: CGPoint(x: 500, y: 22)))
        XCTAssertNil(layout.target(at: CGPoint(x: 150, y: 100)))
    }

    func testLastVisibleRowTargetsItsLazySuccessorInsteadOfPrematureEnd() throws {
        let visibleID = UUID()
        let offscreenID = UUID()
        let layout = try XCTUnwrap(
            ClipboardPinnedDropLayout(
                rows: [
                    .init(
                        itemID: visibleID,
                        nextItemID: offscreenID,
                        frame: CGRect(x: 0, y: 0, width: 300, height: 44)
                    )
                ],
                isFlipped: true
            )
        )

        XCTAssertEqual(
            layout.target(at: CGPoint(x: 150, y: 40))?.destination,
            .before(offscreenID)
        )
    }
}

final class ClipboardPinnedAutoscrollPolicyTests: XCTestCase {
    func testAutoscrollIsIdleAwayFromViewportEdges() {
        XCTAssertEqual(
            ClipboardPinnedAutoscrollPolicy.delta(
                pointerY: 150,
                scrollOffset: 100,
                viewportHeight: 200
            ),
            0
        )
    }

    func testAutoscrollAcceleratesTowardBothViewportEdges() {
        XCTAssertEqual(
            ClipboardPinnedAutoscrollPolicy.delta(
                pointerY: 100,
                scrollOffset: 100,
                viewportHeight: 200
            ),
            -ClipboardPinnedAutoscrollPolicy.maximumStep
        )
        XCTAssertEqual(
            ClipboardPinnedAutoscrollPolicy.delta(
                pointerY: 300,
                scrollOffset: 100,
                viewportHeight: 200
            ),
            ClipboardPinnedAutoscrollPolicy.maximumStep
        )
    }
}
