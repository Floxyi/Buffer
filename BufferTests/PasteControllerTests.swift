import AppKit
import XCTest

@testable import Buffer

@MainActor
final class PasteControllerTests: XCTestCase {
    func testCopyReturnsWriterReceipt() async throws {
        let writer = RecordingControllerPayloadWriter()
        let controller = makeController(payloadWriter: writer)

        let receipt = try await controller.copyToClipboard([.text("single")])

        XCTAssertEqual(receipt, PasteboardWriteReceipt(changeCount: 1))
        XCTAssertEqual(writer.payloads, [.string("single")])
    }

    func testCopyMultipleTextJoinsInActionOrder() async throws {
        let writer = RecordingControllerPayloadWriter()
        let controller = makeController(payloadWriter: writer)

        _ = try await controller.copyToClipboard([.text("first"), .text("second")])

        XCTAssertEqual(writer.payloads, [.string("first\nsecond")])
    }

    func testPrepareMixedPasteCreatesOrderedTextAndImageSteps() async throws {
        let store = makeStore()
        let filename = try XCTUnwrap(store.saveImage(makePNGData()))
        let exporter = RecordingControllerImageExporter(
            tempURLs: ["image-0001.png": URL(fileURLWithPath: "/tmp/image-0001.png")]
        )
        let controller = makeController(store: store, imageExporter: exporter)

        let plan = try await controller.preparePastePlan(for: [
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
        let plan = try await controller.preparePastePlan(for: [.text("hello")])
        var receipts: [PasteboardWriteReceipt] = []

        let outcome = await controller.executePaste(
            plan,
            target: makeTarget(),
            suppressCapture: { receipts.append($0) }
        )

        guard case .success = outcome else { return XCTFail("Expected successful paste") }
        XCTAssertEqual(receipts, [PasteboardWriteReceipt(changeCount: 1)])
    }

    func testFailedMultiImageCopyRemovesPreparedTemporaryAssets() async throws {
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

        do {
            _ = try await controller.copyToClipboard([
                .image(filename: filename),
                .image(filename: filename),
            ])
            XCTFail("Expected copy to fail")
        } catch {
            let removedSessionCount = await exporter.removedSessionCount
            XCTAssertEqual(removedSessionCount, 1)
        }
    }

    func testImageDataEncoderProducesTIFFPayload() {
        XCTAssertNotNil(PasteImageDataEncoder.tiffData(from: makePNGData()))
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
final class HistoryPasteCoordinatorTests: XCTestCase {
    func testSuccessfulPasteUsesPreparedSelectionAndCommitsExactlyOnce() async {
        let pasteController = RecordingHistoryPasteController()
        let delegate = RecordingHistoryPasteDelegate()
        let coordinator = HistoryPasteCoordinator(
            pasteController: pasteController,
            suppressCapturedChange: { _ in },
            openPermissionSettings: {}
        )
        coordinator.delegate = delegate
        coordinator.beginSession(target: makeTarget())
        let selectedItem = ClipboardItem.text("selected")

        coordinator.paste([selectedItem])

        await eventually { delegate.commitCount == 1 }
        XCTAssertEqual(pasteController.preparedItemIDs, [[selectedItem.id]])
        XCTAssertEqual(pasteController.completedPlanCount, 1)
        XCTAssertEqual(delegate.orderOutCount, 1)
        XCTAssertFalse(coordinator.state.isPasteInProgress)
        XCTAssertNil(coordinator.state.failure)
    }

    func testPermissionRecoveryOrdersOutPanelBeforeOpeningSettings() async {
        let pasteController = RecordingHistoryPasteController(hasPostEventAccess: false)
        let delegate = RecordingHistoryPasteDelegate()
        var permissionSettingsOpenCount = 0
        let coordinator = HistoryPasteCoordinator(
            pasteController: pasteController,
            suppressCapturedChange: { _ in },
            openPermissionSettings: { permissionSettingsOpenCount += 1 }
        )
        coordinator.delegate = delegate
        coordinator.beginSession(target: makeTarget())

        coordinator.paste([.text("selected")])
        await eventually { coordinator.state.failure?.recovery == .requestPermission }
        coordinator.requestPermission()

        XCTAssertNil(coordinator.state.failure)
        XCTAssertFalse(coordinator.state.isPasteInProgress)
        XCTAssertEqual(delegate.permissionSettingsCount, 1)
        XCTAssertEqual(delegate.failurePresentationCount, 1)
        XCTAssertEqual(delegate.failureDismissalCount, 0)
        XCTAssertEqual(permissionSettingsOpenCount, 1)
        XCTAssertEqual(pasteController.permissionRequestCount, 1)
        XCTAssertEqual(pasteController.discardedPlanCount, 1)
        XCTAssertEqual(delegate.orderOutCount, 0)
    }

    func testPermissionFailureBlocksRepeatedPasteCommandsUntilResolved() async {
        let pasteController = RecordingHistoryPasteController(hasPostEventAccess: false)
        let coordinator = HistoryPasteCoordinator(
            pasteController: pasteController,
            suppressCapturedChange: { _ in },
            openPermissionSettings: {}
        )
        coordinator.beginSession(target: makeTarget())

        coordinator.paste([.text("selected")])
        await eventually { coordinator.state.failure?.recovery == .requestPermission }
        let presentedFailure = coordinator.state.failure

        coordinator.paste([.text("selected again")])
        await Task.yield()

        XCTAssertTrue(coordinator.state.blocksPasteAttempt)
        XCTAssertEqual(coordinator.state.failure, presentedFailure)
        XCTAssertEqual(pasteController.preparedItemIDs.count, 1)
    }

    func testDismissingFailureBalancesPanelPresentationLifecycle() async {
        let pasteController = RecordingHistoryPasteController(hasPostEventAccess: false)
        let delegate = RecordingHistoryPasteDelegate()
        let coordinator = HistoryPasteCoordinator(
            pasteController: pasteController,
            suppressCapturedChange: { _ in },
            openPermissionSettings: {}
        )
        coordinator.delegate = delegate
        coordinator.beginSession(target: makeTarget())

        coordinator.paste([.text("selected")])
        await eventually { coordinator.state.failure != nil }
        coordinator.dismissFailure()

        XCTAssertEqual(delegate.failurePresentationCount, 1)
        XCTAssertEqual(delegate.failureDismissalCount, 1)
        XCTAssertNil(coordinator.state.failure)
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
}

@MainActor
private final class RecordingHistoryPasteController: PasteControlling {
    let hasPostEventAccess: Bool
    private(set) var preparedItemIDs: [[UUID]] = []
    private(set) var completedPlanCount = 0
    private(set) var discardedPlanCount = 0
    private(set) var permissionRequestCount = 0

    init(hasPostEventAccess: Bool = true) {
        self.hasPostEventAccess = hasPostEventAccess
    }

    func applicationTarget(for application: NSRunningApplication?) -> ApplicationTarget? { nil }

    func preparePastePlan(for items: [ClipboardItem]) async throws -> PastePlan {
        preparedItemIDs.append(items.map(\.id))
        return PastePlan(
            id: UUID(),
            steps: [PasteStep(payload: .string("prepared"), delayBeforeExecution: 0)],
            temporaryAssetSessionID: nil
        )
    }

    func executePaste(
        _ plan: PastePlan,
        target: ApplicationTarget?,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome {
        .success
    }

    func copyToClipboard(_ items: [ClipboardItem]) async throws -> PasteboardWriteReceipt {
        PasteboardWriteReceipt(changeCount: 1)
    }

    func cancelPaste() {}

    func completePastePlan(_ plan: PastePlan) {
        completedPlanCount += 1
    }

    func discardPastePlan(_ plan: PastePlan) {
        discardedPlanCount += 1
    }

    func requestPostEventAccess() -> Bool {
        permissionRequestCount += 1
        return hasPostEventAccess
    }

    func saveImageToDisk(_ image: NSImage) {}
}

@MainActor
private final class RecordingHistoryPasteDelegate: HistoryPasteCoordinatorDelegate {
    private(set) var failurePresentationCount = 0
    private(set) var failureDismissalCount = 0
    private(set) var orderOutCount = 0
    private(set) var permissionSettingsCount = 0
    private(set) var restoreCount = 0
    private(set) var commitCount = 0

    func pasteCoordinatorPresentFailure(_ failure: HistoryPasteFailurePresentation) {
        failurePresentationCount += 1
    }

    func pasteCoordinatorDidDismissFailure() {
        failureDismissalCount += 1
    }

    func pasteCoordinatorWillOrderOutForPaste() {
        orderOutCount += 1
    }

    func pasteCoordinatorWillOpenPermissionSettings() {
        permissionSettingsCount += 1
    }

    func pasteCoordinatorShouldRestorePanel() {
        restoreCount += 1
    }

    func pasteCoordinatorDidCommitPaste() {
        commitCount += 1
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

private actor RecordingControllerImageExporter: PasteTemporaryAssetExporting {
    private(set) var removedSessionIDs: [UUID] = []
    private let tempURLs: [String: URL]

    init(tempURLs: [String: URL] = [:]) {
        self.tempURLs = tempURLs
    }

    var removedSessionCount: Int { removedSessionIDs.count }

    func saveImageDataToTemp(_ data: Data, sessionID: UUID, fileName: String) -> URL? {
        tempURLs[fileName]
    }

    func removePasteSession(_ sessionID: UUID) {
        removedSessionIDs.append(sessionID)
    }

    func removeStalePasteSessions() {}

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
