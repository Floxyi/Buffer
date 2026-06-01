import XCTest
@testable import Buffer

@MainActor
final class PastePayloadBuilderTests: XCTestCase {
    func testCopyPayloadForMultipleTextItemsJoinsWithNewlines() {
        let builder = PastePayloadBuilder(
            store: makeStore(),
            imageExporter: FakePasteImageExporter()
        )

        let payload = builder.copyPayload(for: [
            .text("first"),
            .text("second")
        ])

        guard case .string(let text)? = payload else {
            return XCTFail("Expected joined string payload")
        }
        XCTAssertEqual(text, "first\nsecond")
    }

    func testPastePayloadForImagePrefersTempFileURL() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let expectedURL = URL(fileURLWithPath: "/tmp/image-0001.png")
        let builder = PastePayloadBuilder(
            store: store,
            imageExporter: FakePasteImageExporter(tempURLs: ["image-0001.png": expectedURL])
        )

        let payload = builder.pastePayload(for: item)

        guard case .fileURLs(let urls)? = payload else {
            return XCTFail("Expected file URL payload")
        }
        XCTAssertEqual(urls, [expectedURL])
    }

    func testBatchPayloadSeparatesTextAndImageFiles() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let builder = PastePayloadBuilder(
            store: store,
            imageExporter: FakePasteImageExporter(tempURLs: ["image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")])
        )

        let batch = builder.batchPayload(for: [.text("hello"), item])

        XCTAssertEqual(batch.textPayload, "hello")
        XCTAssertEqual(batch.imageFileURLs.map(\.lastPathComponent), ["image-0001.png"])
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        return ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
    }
}

@MainActor
private struct FakePasteImageExporter: PasteImageExporting {
    var tempURLs: [String: URL] = [:]

    func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        tempURLs[fileName]
    }

    func saveImageToDisk(_ image: NSImage) {}
}
