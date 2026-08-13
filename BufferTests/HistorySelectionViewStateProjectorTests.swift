import XCTest

@testable import Buffer

final class HistorySelectionViewStateProjectorTests: XCTestCase {
    func testProjectCopiesSelectionStateFields() {
        let firstID = UUID()
        let secondID = UUID()
        let state = HistorySelectionState(
            selectedIDs: [firstID, secondID],
            selectedActionOrderIDs: [secondID, firstID],
            selectedIndex: 3,
            selectedID: secondID,
            selectionAnchor: firstID
        )

        let projection = HistorySelectionViewStateProjector().project(state)

        XCTAssertEqual(projection.selectedIDs, [firstID, secondID])
        XCTAssertEqual(projection.selectedActionOrderIDs, [secondID, firstID])
        XCTAssertEqual(projection.selectedIndex, 3)
        XCTAssertEqual(projection.selectedID, secondID)
    }
}
