import XCTest

@testable import Buffer

@MainActor
final class PastePayloadBuilderTests: XCTestCase {
    func testCopyPayloadForMultipleTextItemsJoinsWithNewlines() throws {
        let builder = PastePayloadBuilder(
            store: makeStore(),
            imageExporter: FakePasteImageExporter()
        )

        let preparation = try builder.prepareCopyPayload(for: [
            .text("first"),
            .text("second"),
        ])

        guard case .string(let text) = preparation.payload else {
            return XCTFail("Expected joined string payload")
        }
        XCTAssertEqual(text, "first\nsecond")
        XCTAssertNil(preparation.temporaryAssetSessionID)
    }

    func testPastePlanForImagePrefersSessionScopedTempFileURL() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let expectedURL = URL(fileURLWithPath: "/tmp/image-0001.png")
        let builder = PastePayloadBuilder(
            store: store,
            imageExporter: FakePasteImageExporter(tempURLs: ["image-0001.png": expectedURL])
        )

        let plan = try builder.makePastePlan(for: [item])

        guard case .fileURLs(let urls) = plan.steps.first?.payload else {
            return XCTFail("Expected file URL payload")
        }
        XCTAssertEqual(urls, [expectedURL])
        XCTAssertNotNil(plan.temporaryAssetSessionID)
    }

    func testMixedPastePlanSeparatesTextAndImageFilesInOrder() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let builder = PastePayloadBuilder(
            store: store,
            imageExporter: FakePasteImageExporter(tempURLs: [
                "image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")
            ])
        )

        let plan = try builder.makePastePlan(for: [.text("hello"), item])

        XCTAssertEqual(
            plan.steps.map(\.payload),
            [
                .string("hello"),
                .fileURLs([URL(fileURLWithPath: "/tmp/image-0001.png")]),
            ])
        XCTAssertEqual(plan.steps.map(\.delayBeforeExecution), [0, 0.4])
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

    func saveImageToTemp(_ image: NSImage, sessionID: UUID, fileName: String) -> URL? {
        tempURLs[fileName]
    }

    func removePasteSession(_ sessionID: UUID) {}
    func removeStalePasteSessions() {}
    func saveImageToDisk(_ image: NSImage) {}
}
