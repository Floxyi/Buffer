import XCTest
@testable import Buffer

final class ClipboardStoragePathsTests: XCTestCase {
    func testCustomInitializerPreservesPaths() {
        let root = URL(fileURLWithPath: "/tmp/BufferTests", isDirectory: true)
        let paths = ClipboardStoragePaths(
            storageDirectory: root,
            historyFileURL: root.appendingPathComponent("history.json"),
            imagesDirectory: root.appendingPathComponent("images", isDirectory: true),
            textsDirectory: root.appendingPathComponent("texts", isDirectory: true)
        )

        XCTAssertEqual(paths.storageDirectory.path, "/tmp/BufferTests")
        XCTAssertEqual(paths.historyFileURL.lastPathComponent, "history.json")
        XCTAssertEqual(paths.imagesDirectory.lastPathComponent, "images")
        XCTAssertEqual(paths.textsDirectory.lastPathComponent, "texts")
    }
}
