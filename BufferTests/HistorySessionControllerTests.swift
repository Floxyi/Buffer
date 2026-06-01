import XCTest
@testable import Buffer

final class HistorySessionControllerTests: XCTestCase {
    func testHandleSearchTextChangeSuppressesProgrammaticRebuildOnce() {
        let controller = HistorySessionController()

        let suppressed = controller.handleSearchTextChange(
            state: HistorySessionState(isApplyingProgrammaticSearchChange: true)
        )
        XCTAssertFalse(suppressed.shouldRebuildFilteredItems)
        XCTAssertFalse(suppressed.state.isApplyingProgrammaticSearchChange)

        let normal = controller.handleSearchTextChange(state: suppressed.state)
        XCTAssertTrue(normal.shouldRebuildFilteredItems)
    }

    func testMakeWindowOpenPlanKeepsSelectionWhenConfigured() {
        let controller = HistorySessionController()
        let selectedID = UUID()

        let plan = controller.makeWindowOpenPlan(
            searchText: "needle",
            focusSearch: true,
            currentSelectionIsEmpty: false,
            selectedID: selectedID,
            filteredItems: [ClipboardItem.text("first")],
            historyWindowOpenBehavior: .keepLastSelection
        )

        XCTAssertTrue(plan.shouldIncrementSearchSelectionToken)
        XCTAssertTrue(plan.shouldFocusSearchOnOpen)
        XCTAssertNil(plan.openListScrollRequest)

        guard case .keepCurrentOrSelectTop = plan.selectionPreference else {
            return XCTFail("Expected keepCurrentOrSelectTop selection preference")
        }
    }

    func testMakeWindowOpenPlanSelectsFirstNonPinnedItemAndScrollsToTop() {
        let controller = HistorySessionController()
        let pinned = ClipboardItem(type: .text, textContent: "pinned", isPinned: true)
        let first = ClipboardItem.text("first")
        let second = ClipboardItem.text("second")

        let plan = controller.makeWindowOpenPlan(
            searchText: "",
            focusSearch: false,
            currentSelectionIsEmpty: true,
            selectedID: nil,
            filteredItems: [pinned, first, second],
            historyWindowOpenBehavior: .selectFirstNonPinnedItem
        )

        XCTAssertFalse(plan.shouldIncrementSearchSelectionToken)
        XCTAssertFalse(plan.shouldFocusSearchOnOpen)
        XCTAssertEqual(plan.openListScrollRequest, HistoryOpenListScrollRequest(mode: .scrollToTop))

        guard case .selectPreferred(let preferredID) = plan.selectionPreference else {
            return XCTFail("Expected preferred selection")
        }
        XCTAssertEqual(preferredID, first.id)
    }

    func testMakeJumpToHistoryPlanClearsSearchAndSetsProgrammaticFlag() {
        let controller = HistorySessionController()
        let itemID = UUID()

        let plan = controller.makeJumpToHistoryPlan(
            for: itemID,
            currentSearchText: "needle",
            state: HistorySessionState()
        )

        XCTAssertEqual(plan.searchText, "")
        XCTAssertTrue(plan.shouldRebuildFilteredItems)
        XCTAssertEqual(plan.preferredSelectionID, itemID)
        XCTAssertTrue(plan.state.isApplyingProgrammaticSearchChange)
    }
}
