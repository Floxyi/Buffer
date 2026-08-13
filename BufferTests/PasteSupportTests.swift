import XCTest

@testable import Buffer

@MainActor
final class PasteSupportTests: XCTestCase {
    func testSaveImageToTempWritesPNGFile() async throws {
        let imageData = makePNGData(size: NSSize(width: 9, height: 6), color: .systemGreen)
        let exporter = PasteImageExporter()
        let sessionID = UUID()
        defer { Task { await exporter.removePasteSession(sessionID) } }
        let savedURL = await exporter.saveImageDataToTemp(
            imageData,
            sessionID: sessionID,
            fileName: "paste-support-test.png"
        )
        let url = try XCTUnwrap(savedURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
        XCTAssertEqual(url.lastPathComponent, "paste-support-test.png")
    }
}
