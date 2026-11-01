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

    func testUIValidationConfigurationRequiresExplicitEnableAndIsolatedTemporaryDirectory() {
        let temporaryChild = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferUIValidationTests-\(UUID())", isDirectory: true)

        XCTAssertNil(
            BufferUIValidationConfiguration(
                environment: [
                    "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY": temporaryChild.path
                ],
                arguments: []
            )
        )
        XCTAssertNil(
            BufferUIValidationConfiguration(
                environment: [
                    "BUFFER_UI_VALIDATION": "1",
                    "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY": FileManager.default
                        .temporaryDirectory.path,
                ],
                arguments: []
            )
        )
        XCTAssertNil(
            BufferUIValidationConfiguration(
                environment: [
                    "BUFFER_UI_VALIDATION": "1",
                    "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY": "/Users/shared-buffer-fixture",
                ],
                arguments: []
            )
        )
    }

    func testUIValidationConfigurationCreatesDeterministicClampedFixture() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferUIValidationTests-\(UUID())", isDirectory: true)
        let configuration = try XCTUnwrap(
            BufferUIValidationConfiguration(
                environment: [
                    "BUFFER_UI_VALIDATION": "1",
                    "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY": storageDirectory.path,
                    "BUFFER_UI_VALIDATION_ITEM_COUNT": "5",
                ],
                arguments: []
            )
        )
        defer { configuration.removeStorage() }

        let paths = try configuration.prepareStorage()
        let items = try ClipboardHistoryPersistence(paths: paths).loadHistory()

        XCTAssertEqual(configuration.itemCount, 20)
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(
            items.first?.id,
            UUID(uuidString: "10000000-0000-4000-8000-000000000001")
        )
        XCTAssertTrue(items.prefix(3).allSatisfy(\.isPinned))
        XCTAssertTrue(items.dropFirst(3).allSatisfy { !$0.isPinned })
    }

    func testUIValidationConfigurationRejectsTemporarySymlinkEscapingIsolation() throws {
        let symlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferUIValidationSymlink-\(UUID())")
        try FileManager.default.createSymbolicLink(
            at: symlink,
            withDestinationURL: FileManager.default.homeDirectoryForCurrentUser
        )
        defer { try? FileManager.default.removeItem(at: symlink) }

        let escapedDirectory = symlink.appendingPathComponent("BufferFixture", isDirectory: true)
        XCTAssertNil(
            BufferUIValidationConfiguration(
                environment: [
                    "BUFFER_UI_VALIDATION": "1",
                    "BUFFER_UI_VALIDATION_STORAGE_DIRECTORY": escapedDirectory.path,
                ],
                arguments: []
            )
        )
    }
}
