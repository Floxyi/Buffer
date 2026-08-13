import XCTest

@testable import Buffer

@MainActor
final class PastePayloadBuilderTests: XCTestCase {
    func testCopyPayloadForMultipleTextItemsJoinsWithNewlines() async throws {
        let builder = PastePayloadBuilder(
            contentReader: makeStore(),
            imageExporter: FakePasteImageExporter()
        )

        let preparation = try await builder.prepareCopyPayload(for: [
            .text("first"),
            .text("second"),
        ])

        guard case .string(let text) = preparation.payload else {
            return XCTFail("Expected joined string payload")
        }
        XCTAssertEqual(text, "first\nsecond")
        XCTAssertNil(preparation.temporaryAssetSessionID)
    }

    func testEmailCopyAndPastePreserveOriginalText() async throws {
        let builder = PastePayloadBuilder(
            contentReader: makeStore(),
            imageExporter: FakePasteImageExporter()
        )
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("  person@example.com\n"))
        )

        let copy = try await builder.prepareCopyPayload(for: [item])
        let paste = try await builder.makePastePlan(for: [item])

        XCTAssertEqual(copy.payload, .string("  person@example.com\n"))
        XCTAssertEqual(paste.steps.map(\.payload), [.string("  person@example.com\n")])
    }

    func testPastePlanForImagePrefersSessionScopedTempFileURL() async throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let expectedURL = URL(fileURLWithPath: "/tmp/image-0001.png")
        let builder = PastePayloadBuilder(
            contentReader: store,
            imageExporter: FakePasteImageExporter(tempURLs: ["image-0001.png": expectedURL])
        )

        let plan = try await builder.makePastePlan(for: [item])

        guard case .fileURLs(let urls) = plan.steps.first?.payload else {
            return XCTFail("Expected file URL payload")
        }
        XCTAssertEqual(urls, [expectedURL])
        XCTAssertNotNil(plan.temporaryAssetSessionID)
    }

    func testMixedPastePlanSeparatesTextAndImageFilesInOrder() async throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let item = ClipboardItem.image(filename: filename)
        let builder = PastePayloadBuilder(
            contentReader: store,
            imageExporter: FakePasteImageExporter(tempURLs: [
                "image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")
            ])
        )

        let plan = try await builder.makePastePlan(for: [.text("hello"), item])

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

private struct FakePasteImageExporter: PasteTemporaryAssetExporting {
    var tempURLs: [String: URL] = [:]

    func saveImageDataToTemp(_ data: Data, sessionID: UUID, fileName: String) async -> URL? {
        tempURLs[fileName]
    }

    func removePasteSession(_ sessionID: UUID) async {}
    func removeStalePasteSessions() async {}
}
