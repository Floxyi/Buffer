import XCTest
@testable import Buffer

final class ClipboardItemSourceApplicationTests: XCTestCase {
    func testMapsSourceApplicationInfoIntoClipboardItemFactories() {
        let sourceApplication = SourceApplicationInfo(
            name: "Notes",
            bundleIdentifier: "com.apple.Notes",
            bundlePath: "/Applications/Notes.app"
        )

        let item = ClipboardItem.text("hello", sourceApp: sourceApplication)

        XCTAssertEqual(item.sourceApp, "Notes")
        XCTAssertEqual(item.sourceAppBundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(item.sourceAppBundlePath, "/Applications/Notes.app")
    }

    func testSourceAppDisplayNameFallsBackToBundlePath() {
        let item = ClipboardItem(
            type: .text,
            sourceApp: nil,
            sourceAppBundleIdentifier: nil,
            sourceAppBundlePath: "/Applications/Preview.app",
            textContent: "hello"
        )

        XCTAssertEqual(item.sourceAppDisplayName, "Preview")
    }
}
