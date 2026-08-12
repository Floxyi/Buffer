import XCTest
@testable import Buffer

@MainActor
final class PasteSupportTests: XCTestCase {
    func testSaveImageToTempWritesPNGFile() throws {
        let image = makeTestImage(size: NSSize(width: 9, height: 6), color: .systemGreen)
        let exporter = PasteImageExporter()
        let sessionID = UUID()
        defer { exporter.removePasteSession(sessionID) }
        let url = try XCTUnwrap(
            exporter.saveImageToTemp(
                image,
                sessionID: sessionID,
                fileName: "paste-support-test.png"
            ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
        XCTAssertEqual(url.lastPathComponent, "paste-support-test.png")
    }
}
