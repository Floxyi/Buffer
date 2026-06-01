import AppKit
import XCTest

@testable import Buffer

@MainActor
final class PasteControllerTests: XCTestCase {
    func testCopySingleTextUsesInjectedPayloadWriter() {
        let writer = RecordingPastePayloadWriter()
        let controller = PasteController(
            store: makeStore(),
            automation: RecordingPasteAutomation(),
            imageExporter: RecordingPasteImageExporter(),
            payloadWriter: writer,
            scheduler: RecordingPasteScheduler()
        )

        controller.copyToClipboard(.text("single"))

        XCTAssertEqual(writer.payloads.count, 1)
        guard case .string(let text) = writer.payloads[0] else {
            return XCTFail("Expected string payload")
        }
        XCTAssertEqual(text, "single")
    }

    func testCopyMultipleUsesInjectedPayloadWriter() {
        let writer = RecordingPastePayloadWriter()
        let controller = PasteController(
            store: makeStore(),
            automation: RecordingPasteAutomation(),
            imageExporter: RecordingPasteImageExporter(),
            payloadWriter: writer,
            scheduler: RecordingPasteScheduler()
        )

        controller.copyMultipleToClipboard([.text("first"), .text("second")])

        XCTAssertEqual(writer.payloads.count, 1)
        guard case .string(let text) = writer.payloads[0] else {
            return XCTFail("Expected string payload")
        }
        XCTAssertEqual(text, "first\nsecond")
    }

    func testPasteTextWritesPayloadAndTriggersAutomation() {
        let writer = RecordingPastePayloadWriter()
        let automation = RecordingPasteAutomation()
        let controller = PasteController(
            store: makeStore(),
            automation: automation,
            imageExporter: RecordingPasteImageExporter(),
            payloadWriter: writer,
            scheduler: RecordingPasteScheduler()
        )
        var ignoreCount = 0

        controller.paste(.text("paste me"), previousApp: nil) {
            ignoreCount += 1
        }

        XCTAssertEqual(writer.payloads.count, 1)
        guard case .string(let text) = writer.payloads[0] else {
            return XCTFail("Expected string payload")
        }
        XCTAssertEqual(text, "paste me")
        XCTAssertEqual(automation.delays, [0.1])
        XCTAssertEqual(ignoreCount, 1)
    }

    func testPasteMultipleMixedPayloadSchedulesDelayedImagePaste() throws {
        let writer = RecordingPastePayloadWriter()
        let automation = RecordingPasteAutomation()
        let scheduler = RecordingPasteScheduler()
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let controller = PasteController(
            store: store,
            automation: automation,
            imageExporter: RecordingPasteImageExporter(
                tempURLs: ["image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")]
            ),
            payloadWriter: writer,
            scheduler: scheduler
        )
        var ignoreCount = 0

        controller.pasteMultiple([.text("hello"), .image(filename: filename)], previousApp: nil) {
            ignoreCount += 1
        }

        XCTAssertEqual(writer.payloads.count, 1)
        XCTAssertEqual(automation.delays, [0.1])
        XCTAssertEqual(scheduler.scheduledDelays, [0.5])
        XCTAssertEqual(ignoreCount, 1)

        scheduler.runScheduledOperations()

        XCTAssertEqual(writer.payloads.count, 2)
        guard case .fileURLs(let urls) = writer.payloads[1] else {
            return XCTFail("Expected file URL payload")
        }
        XCTAssertEqual(urls.map(\.lastPathComponent), ["image-0001.png"])
        XCTAssertEqual(automation.delays, [0.1, 0.05])
        XCTAssertEqual(ignoreCount, 2)
    }

    func testSaveImageToDiskDelegatesToExporter() {
        let exporter = RecordingPasteImageExporter()
        let controller = PasteController(
            store: makeStore(),
            automation: RecordingPasteAutomation(),
            imageExporter: exporter,
            payloadWriter: RecordingPastePayloadWriter(),
            scheduler: RecordingPasteScheduler()
        )
        let image = makeTestImage()

        controller.saveImageToDisk(image)

        XCTAssertEqual(exporter.savedImages.count, 1)
        XCTAssertEqual(exporter.savedImages[0].size, image.size)
    }

    private func makeStore() -> ClipboardStore {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        return ClipboardStore(settingsManager: settings, storagePaths: TestStorageFactory.makePaths())
    }
}

private final class RecordingPastePayloadWriter: PastePayloadWriting {
    private(set) var payloads: [PastePayload] = []

    func write(_ payload: PastePayload) {
        payloads.append(payload)
    }
}

private final class RecordingPasteAutomation: PasteAutomating {
    private(set) var delays: [TimeInterval] = []

    func simulatePaste(after delay: TimeInterval) {
        delays.append(delay)
    }
}

private final class RecordingPasteScheduler: PasteScheduling {
    private(set) var scheduledDelays: [TimeInterval] = []
    private var operations: [MainActorOperationBox] = []

    func schedule(after delay: TimeInterval, operation: MainActorOperationBox) {
        scheduledDelays.append(delay)
        operations.append(operation)
    }

    @MainActor
    func runScheduledOperations() {
        let pendingOperations = operations
        operations.removeAll()
        pendingOperations.forEach { $0.run() }
    }
}

@MainActor
private final class RecordingPasteImageExporter: PasteImageExporting {
    private(set) var savedImages: [NSImage] = []
    private let tempURLs: [String: URL]

    init(tempURLs: [String: URL] = [:]) {
        self.tempURLs = tempURLs
    }

    func saveImageToTemp(_ image: NSImage, fileName: String) -> URL? {
        tempURLs[fileName]
    }

    func saveImageToDisk(_ image: NSImage) {
        savedImages.append(image)
    }
}
