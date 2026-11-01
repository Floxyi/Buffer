import XCTest

final class HistoryDeletionScrollUITests: XCTestCase {
    @MainActor
    func testDeletingDeepVisibleItemsKeepsViewportStableWithoutIntermediateFlicker() async throws {
        continueAfterFailure = false

        let application = XCUIApplication(
            bundleIdentifier: "de.floxyi.buffer.ui-validation"
        )
        application.terminate()
        application.launch()

        let scrollView = application.scrollViews["historyList.scrollView"]
        let scrollViewExists = await waitForExistence(of: scrollView, timeout: .seconds(10))
        XCTAssertTrue(scrollViewExists, application.debugDescription)
        let fixtureRow = application.buttons[Self.fixtureIdentifier(index: 3)]
        let fixtureExists = await waitForExistence(of: fixtureRow, timeout: .seconds(10))
        XCTAssertTrue(
            fixtureExists,
            "Buffer did not launch with its isolated UI-validation history: \(application.debugDescription)"
        )
        scrollDeepIntoHistory(in: scrollView)
        let visibleRows = visibleHistoryRows(in: scrollView, application: application)
        XCTAssertGreaterThanOrEqual(visibleRows.count, 4, application.debugDescription)

        let targetIndex = visibleRows.count / 2
        let target = visibleRows[targetIndex]
        let anchor = visibleRows[targetIndex - 1]
        let targetIdentifier = target.identifier
        let anchorIdentifier = anchor.identifier
        let anchorFrame = anchor.frame

        target.click()
        target.typeKey(.delete, modifierFlags: .command)

        await assertStableFrame(
            in: application,
            anchorIdentifier: anchorIdentifier,
            expected: anchorFrame,
            removedIdentifier: targetIdentifier
        )
    }

    @MainActor
    private func scrollDeepIntoHistory(in scrollView: XCUIElement) {
        for _ in 0..<9 {
            scrollView.scroll(byDeltaX: 0, deltaY: -520)
        }
    }

    @MainActor
    private func visibleHistoryRows(
        in scrollView: XCUIElement,
        application: XCUIApplication
    ) -> [XCUIElement] {
        let viewport = scrollView.frame
        let query = application.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "historyItem.")
        )
        return query.allElementsBoundByIndex
            .filter { element in
                let frame = element.frame
                return frame.minY >= viewport.minY
                    && frame.maxY <= viewport.maxY
            }
            .sorted { $0.frame.minY < $1.frame.minY }
    }

    @MainActor
    private func assertStableFrame(
        in application: XCUIApplication,
        anchorIdentifier: String,
        expected expectedFrame: CGRect,
        removedIdentifier: String
    ) async {
        let deadline = Date().addingTimeInterval(3)
        var largestVerticalDrift: CGFloat = 0
        var anchorWasMissing = false

        repeat {
            let anchor = application.buttons[anchorIdentifier]
            if anchor.exists {
                largestVerticalDrift = max(
                    largestVerticalDrift,
                    abs(anchor.frame.minY - expectedFrame.minY)
                )
            } else {
                anchorWasMissing = true
            }

            let removedElement = application.buttons[removedIdentifier]
            if !removedElement.exists {
                break
            }
            try? await Task.sleep(for: .milliseconds(8))
        } while Date() < deadline

        let removedElement = application.buttons[removedIdentifier]
        XCTAssertFalse(
            removedElement.exists,
            "The selected row was not deleted: \(removedElement.debugDescription)"
        )
        XCTAssertFalse(anchorWasMissing, "The visible anchor disappeared during deletion")
        XCTAssertLessThanOrEqual(
            largestVerticalDrift,
            1,
            "The viewport drifted by \(largestVerticalDrift) points during deletion"
        )
        let finalAnchor = application.buttons[anchorIdentifier]
        XCTAssertTrue(finalAnchor.exists, "The visible anchor disappeared after deletion")
        XCTAssertEqual(finalAnchor.frame.minY, expectedFrame.minY, accuracy: 1)
    }

    @MainActor
    private func waitForExistence(
        of element: XCUIElement,
        timeout: Duration
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if element.exists {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return element.exists
    }

    private static func fixtureIdentifier(index: Int) -> String {
        let suffix = String(format: "%012X", index + 1)
        return "historyItem.10000000-0000-4000-8000-\(suffix)"
    }
}
