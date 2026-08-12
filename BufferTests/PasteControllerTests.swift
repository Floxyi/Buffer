import AppKit
import XCTest

@testable import Buffer

@MainActor
final class PasteControllerTests: XCTestCase {
    func testCopyReturnsWriterReceipt() throws {
        let writer = RecordingControllerPayloadWriter()
        let controller = makeController(payloadWriter: writer)

        let receipt = try controller.copyToClipboard([.text("single")])

        XCTAssertEqual(receipt, PasteboardWriteReceipt(changeCount: 1))
        XCTAssertEqual(writer.payloads, [.string("single")])
    }

    func testCopyMultipleTextJoinsInActionOrder() throws {
        let writer = RecordingControllerPayloadWriter()
        let controller = makeController(payloadWriter: writer)

        _ = try controller.copyToClipboard([.text("first"), .text("second")])

        XCTAssertEqual(writer.payloads, [.string("first\nsecond")])
    }

    func testPrepareMixedPasteCreatesOrderedTextAndImageSteps() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let exporter = RecordingControllerImageExporter(
            tempURLs: ["image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")]
        )
        let controller = makeController(store: store, imageExporter: exporter)

        let plan = try controller.preparePastePlan(for: [
            .text("hello"),
            .image(filename: filename),
        ])

        XCTAssertEqual(
            plan.steps.map(\.payload),
            [
                .string("hello"),
                .fileURLs([URL(fileURLWithPath: "/tmp/image-0001.png")]),
            ])
        XCTAssertEqual(plan.steps.map(\.delayBeforeExecution), [0, 0.4])
        XCTAssertNotNil(plan.temporaryAssetSessionID)
    }

    func testExecutePassesReceiptsToCaptureSuppression() async throws {
        let writer = RecordingControllerPayloadWriter()
        let controller = makeController(payloadWriter: writer)
        let plan = try controller.preparePastePlan(for: [.text("hello")])
        var receipts: [PasteboardWriteReceipt] = []

        let outcome = await controller.executePaste(
            plan,
            target: makeTarget(),
            suppressCapture: { receipts.append($0) }
        )

        guard case .success = outcome else { return XCTFail("Expected successful paste") }
        XCTAssertEqual(receipts, [PasteboardWriteReceipt(changeCount: 1)])
    }

    func testFailedMultiImageCopyRemovesPreparedTemporaryAssets() throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let exporter = RecordingControllerImageExporter(tempURLs: [
            "image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png"),
            "image-0002.png": URL(fileURLWithPath: "/tmp/image-0002.png"),
        ])
        let writer = RecordingControllerPayloadWriter(writeError: .writeRejected)
        let controller = makeController(
            store: store,
            imageExporter: exporter,
            payloadWriter: writer
        )

        XCTAssertThrowsError(
            try controller.copyToClipboard([
                .image(filename: filename),
                .image(filename: filename),
            ]))
        XCTAssertEqual(exporter.removedSessionIDs.count, 1)
    }

    func testSaveImageToDiskDelegatesToExporter() {
        let exporter = RecordingControllerImageExporter()
        let controller = makeController(imageExporter: exporter)
        let image = makeTestImage()

        controller.saveImageToDisk(image)

        XCTAssertEqual(exporter.savedImages.map(\.size), [image.size])
    }

    private func makeController(
        store: ClipboardStore? = nil,
        imageExporter: RecordingControllerImageExporter = RecordingControllerImageExporter(),
        payloadWriter: RecordingControllerPayloadWriter = RecordingControllerPayloadWriter()
    ) -> PasteController {
        PasteController(
            store: store ?? makeStore(),
            imageExporter: imageExporter,
            payloadWriter: payloadWriter,
            focusRestorer: SuccessfulControllerFocusRestorer(),
            eventSender: SuccessfulControllerEventSender(),
            sleeper: ImmediateControllerSleeper(),
            targetResolver: { _ in self.makeTarget() }
        )
    }

    private func makeTarget() -> ApplicationTarget {
        ApplicationTarget(
            processIdentifier: 42,
            applicationName: "Target",
            activate: {},
            isReady: { true },
            isTerminated: { false }
        )
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
private final class RecordingControllerPayloadWriter: PastePayloadWriting {
    private(set) var payloads: [PastePayload] = []
    private let writeError: PasteboardWriteError?

    init(writeError: PasteboardWriteError? = nil) {
        self.writeError = writeError
    }

    func write(_ payload: PastePayload) throws -> PasteboardWriteReceipt {
        payloads.append(payload)
        if let writeError {
            throw writeError
        }
        return PasteboardWriteReceipt(changeCount: payloads.count)
    }
}

@MainActor
private final class RecordingControllerImageExporter: PasteImageExporting {
    private(set) var savedImages: [NSImage] = []
    private(set) var removedSessionIDs: [UUID] = []
    private let tempURLs: [String: URL]

    init(tempURLs: [String: URL] = [:]) {
        self.tempURLs = tempURLs
    }

    func saveImageToTemp(_ image: NSImage, sessionID: UUID, fileName: String) -> URL? {
        tempURLs[fileName]
    }

    func removePasteSession(_ sessionID: UUID) {
        removedSessionIDs.append(sessionID)
    }

    func removeStalePasteSessions() {}

    func saveImageToDisk(_ image: NSImage) {
        savedImages.append(image)
    }
}

@MainActor
private struct SuccessfulControllerFocusRestorer: PasteFocusRestoring {
    func restoreFocus(to target: ApplicationTarget) async -> Bool { true }
}

@MainActor
private struct SuccessfulControllerEventSender: PasteEventSending {
    var hasPostEventAccess: Bool { true }
    func requestPostEventAccess() -> Bool { true }
    func sendPasteShortcut() -> Bool { true }
}

@MainActor
private struct ImmediateControllerSleeper: PasteSleeping {
    func sleep(for interval: TimeInterval) async throws {}
}
