import XCTest
@testable import Buffer

@MainActor
final class PasteSessionCoordinatorTests: XCTestCase {
    func testPasteWritesPayloadActivatesAndSimulatesPaste() {
        let writer = RecordingPastePayloadWriter()
        let automation = RecordingPasteAutomation()
        let scheduler = RecordingPasteScheduler()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            automation: automation,
            scheduler: scheduler
        )
        var ignoreCount = 0
        var activationCount = 0

        coordinator.paste(
            payload: .string("hello"),
            activatePreviousApp: { activationCount += 1 },
            ignoreNextCapturedChange: { ignoreCount += 1 }
        )

        XCTAssertEqual(writer.payloads.count, 1)
        XCTAssertEqual(automation.delays, [0.1])
        XCTAssertEqual(ignoreCount, 1)
        XCTAssertEqual(activationCount, 1)
        XCTAssertTrue(scheduler.scheduledDelays.isEmpty)
    }

    func testPasteMultipleWithMixedPayloadSchedulesImageFollowUp() {
        let writer = RecordingPastePayloadWriter()
        let automation = RecordingPasteAutomation()
        let scheduler = RecordingPasteScheduler()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            automation: automation,
            scheduler: scheduler
        )
        var ignoreCount = 0

        coordinator.pasteMultiple(
            batch: PasteBatchPayload(
                textPayload: "hello",
                imageFileURLs: [URL(fileURLWithPath: "/tmp/image-0001.png")]
            ),
            activatePreviousApp: nil,
            ignoreNextCapturedChange: { ignoreCount += 1 }
        )

        XCTAssertEqual(writer.payloads.count, 1)
        XCTAssertEqual(automation.delays, [0.1])
        XCTAssertEqual(scheduler.scheduledDelays, [0.5])

        scheduler.runScheduledOperations()

        XCTAssertEqual(writer.payloads.count, 2)
        XCTAssertEqual(automation.delays, [0.1, 0.05])
        XCTAssertEqual(ignoreCount, 2)
    }

    func testPasteMultipleWithOnlyImagesSchedulesDelayedImagePaste() {
        let writer = RecordingPastePayloadWriter()
        let automation = RecordingPasteAutomation()
        let scheduler = RecordingPasteScheduler()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            automation: automation,
            scheduler: scheduler
        )
        var activationCount = 0

        coordinator.pasteMultiple(
            batch: PasteBatchPayload(
                textPayload: nil,
                imageFileURLs: [URL(fileURLWithPath: "/tmp/image-0001.png")]
            ),
            activatePreviousApp: { activationCount += 1 },
            ignoreNextCapturedChange: {}
        )

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(scheduler.scheduledDelays, [0.1])
        XCTAssertTrue(writer.payloads.isEmpty)

        scheduler.runScheduledOperations()

        XCTAssertEqual(writer.payloads.count, 1)
        XCTAssertEqual(automation.delays, [0.05])
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
