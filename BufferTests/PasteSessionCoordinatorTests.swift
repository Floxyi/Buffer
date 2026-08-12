import XCTest

@testable import Buffer

@MainActor
final class PasteSessionCoordinatorTests: XCTestCase {
    func testExecuteRestoresFocusBeforeWritingAndSendingShortcut() async {
        var events: [String] = []
        let writer = RecordingTransactionalWriter(onWrite: { events.append("write") })
        let focusRestorer = RecordingFocusRestorer(onRestore: { events.append("focus") })
        let sender = RecordingPasteEventSender(onSend: { events.append("send") })
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: focusRestorer,
            eventSender: sender,
            sleeper: ImmediatePasteSleeper()
        )
        var receipts: [PasteboardWriteReceipt] = []

        let outcome = await coordinator.execute(
            makePlan([.string("hello")]),
            target: makeTarget(),
            suppressCapture: { receipts.append($0) }
        )

        XCTAssertTrue(outcome.isSuccess)
        XCTAssertEqual(events, ["focus", "write", "send"])
        XCTAssertEqual(receipts, [PasteboardWriteReceipt(changeCount: 1)])
    }

    func testMissingDestinationDoesNotWriteOrSend() async {
        let writer = RecordingTransactionalWriter()
        let sender = RecordingPasteEventSender()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: RecordingFocusRestorer(),
            eventSender: sender,
            sleeper: ImmediatePasteSleeper()
        )
        let plan = makePlan([.string("hello")])

        let outcome = await coordinator.execute(plan, target: nil, suppressCapture: { _ in })

        XCTAssertEqual(outcome.failureReason, .missingDestination)
        XCTAssertTrue(writer.payloads.isEmpty)
        XCTAssertEqual(sender.sendCount, 0)
    }

    func testPermissionFailureDoesNotWriteOrHideFailureContext() async {
        let writer = RecordingTransactionalWriter()
        let sender = RecordingPasteEventSender(hasAccess: false)
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: RecordingFocusRestorer(),
            eventSender: sender,
            sleeper: ImmediatePasteSleeper()
        )
        let plan = makePlan([.string("hello")])

        let outcome = await coordinator.execute(
            plan,
            target: makeTarget(),
            suppressCapture: { _ in }
        )

        XCTAssertEqual(outcome.failureReason, .eventPermissionDenied)
        XCTAssertEqual(outcome.remainingPlan, plan)
        XCTAssertTrue(writer.payloads.isEmpty)
    }

    func testFocusTimeoutOccursBeforePasteboardMutation() async {
        let writer = RecordingTransactionalWriter()
        let sender = RecordingPasteEventSender()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: RecordingFocusRestorer(succeeds: false),
            eventSender: sender,
            sleeper: ImmediatePasteSleeper()
        )

        let outcome = await coordinator.execute(
            makePlan([.string("hello")]),
            target: makeTarget(),
            suppressCapture: { _ in }
        )

        XCTAssertEqual(outcome.failureReason, .focusTimeout)
        XCTAssertTrue(writer.payloads.isEmpty)
        XCTAssertEqual(sender.sendCount, 0)
    }

    func testMixedPasteReturnsOnlyUnfinishedStepAfterSecondWriteFailure() async {
        let writer = RecordingTransactionalWriter(failingWriteIndex: 1)
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: RecordingFocusRestorer(),
            eventSender: RecordingPasteEventSender(),
            sleeper: ImmediatePasteSleeper()
        )
        let imagePayload = PastePayload.fileURLs([URL(fileURLWithPath: "/tmp/image.png")])
        let plan = makePlan([.string("hello"), imagePayload])

        let outcome = await coordinator.execute(
            plan,
            target: makeTarget(),
            suppressCapture: { _ in }
        )

        XCTAssertEqual(outcome.completedStepCount, 1)
        XCTAssertEqual(outcome.remainingPlan?.steps.map(\.payload), [imagePayload])
        XCTAssertEqual(writer.payloads, [.string("hello"), imagePayload])
    }

    func testRetryPreservesPartialCompletionContextWhenRemainingStepFailsAgain() async throws {
        let imagePayload = PastePayload.fileURLs([URL(fileURLWithPath: "/tmp/image.png")])
        let initialCoordinator = PasteSessionCoordinator(
            payloadWriter: RecordingTransactionalWriter(failingWriteIndex: 1),
            focusRestorer: RecordingFocusRestorer(),
            eventSender: RecordingPasteEventSender(),
            sleeper: ImmediatePasteSleeper()
        )
        let initialOutcome = await initialCoordinator.execute(
            makePlan([.string("hello"), imagePayload]),
            target: makeTarget(),
            suppressCapture: { _ in }
        )
        let remainingPlan = try XCTUnwrap(initialOutcome.remainingPlan)
        let retryCoordinator = PasteSessionCoordinator(
            payloadWriter: RecordingTransactionalWriter(failingWriteIndex: 0),
            focusRestorer: RecordingFocusRestorer(),
            eventSender: RecordingPasteEventSender(),
            sleeper: ImmediatePasteSleeper()
        )

        let retryOutcome = await retryCoordinator.execute(
            remainingPlan,
            target: makeTarget(),
            suppressCapture: { _ in }
        )

        XCTAssertEqual(retryOutcome.completedStepCount, 1)
        XCTAssertEqual(retryOutcome.remainingPlan?.steps.map(\.payload), [imagePayload])
    }

    func testNewSessionCancelsAWaitingOldSession() async {
        let writer = RecordingTransactionalWriter()
        let focusRestorer = SuspendedFocusRestorer()
        let coordinator = PasteSessionCoordinator(
            payloadWriter: writer,
            focusRestorer: focusRestorer,
            eventSender: RecordingPasteEventSender(),
            sleeper: ImmediatePasteSleeper()
        )
        let target = makeTarget()

        let oldTask = Task {
            await coordinator.execute(
                makePlan([.string("old")]),
                target: target,
                suppressCapture: { _ in }
            )
        }
        await focusRestorer.waitUntilRestoreStarts()

        focusRestorer.shouldSuspend = false
        let newOutcome = await coordinator.execute(
            makePlan([.string("new")]),
            target: target,
            suppressCapture: { _ in }
        )
        focusRestorer.resumeSuspendedRestore()
        let oldOutcome = await oldTask.value

        XCTAssertTrue(newOutcome.isSuccess)
        XCTAssertTrue(oldOutcome.isCancelled)
        XCTAssertEqual(writer.payloads, [.string("new")])
    }

    private func makePlan(_ payloads: [PastePayload]) -> PastePlan {
        PastePlan(
            id: UUID(),
            steps: payloads.enumerated().map { index, payload in
                PasteStep(payload: payload, delayBeforeExecution: index == 0 ? 0 : 0.4)
            },
            temporaryAssetSessionID: nil
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
}

extension PasteOutcome {
    fileprivate var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    fileprivate var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    fileprivate var failureReason: PasteFailure? {
        guard case .failure(let failure, _, _) = self else { return nil }
        return failure
    }

    fileprivate var remainingPlan: PastePlan? {
        guard case .failure(_, let plan, _) = self else { return nil }
        return plan
    }

    fileprivate var completedStepCount: Int? {
        guard case .failure(_, _, let count) = self else { return nil }
        return count
    }
}

@MainActor
private final class RecordingTransactionalWriter: PastePayloadWriting {
    private(set) var payloads: [PastePayload] = []
    private let failingWriteIndex: Int?
    private let onWrite: () -> Void

    init(failingWriteIndex: Int? = nil, onWrite: @escaping () -> Void = {}) {
        self.failingWriteIndex = failingWriteIndex
        self.onWrite = onWrite
    }

    func write(_ payload: PastePayload) throws -> PasteboardWriteReceipt {
        let index = payloads.count
        payloads.append(payload)
        onWrite()
        if failingWriteIndex == index {
            throw PasteboardWriteError.writeRejected
        }
        return PasteboardWriteReceipt(changeCount: index + 1)
    }
}

@MainActor
private final class RecordingFocusRestorer: PasteFocusRestoring {
    private let succeeds: Bool
    private let onRestore: () -> Void

    init(succeeds: Bool = true, onRestore: @escaping () -> Void = {}) {
        self.succeeds = succeeds
        self.onRestore = onRestore
    }

    func restoreFocus(to target: ApplicationTarget) async -> Bool {
        onRestore()
        return succeeds
    }
}

@MainActor
private final class SuspendedFocusRestorer: PasteFocusRestoring {
    var shouldSuspend = true
    private var didStart = false
    private var continuation: CheckedContinuation<Void, Never>?

    func restoreFocus(to target: ApplicationTarget) async -> Bool {
        didStart = true
        guard shouldSuspend else { return true }
        await withCheckedContinuation { continuation = $0 }
        return true
    }

    func waitUntilRestoreStarts() async {
        while !didStart { await Task.yield() }
    }

    func resumeSuspendedRestore() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class RecordingPasteEventSender: PasteEventSending {
    var hasPostEventAccess: Bool
    private(set) var sendCount = 0
    private let onSend: () -> Void

    init(hasAccess: Bool = true, onSend: @escaping () -> Void = {}) {
        self.hasPostEventAccess = hasAccess
        self.onSend = onSend
    }

    func requestPostEventAccess() -> Bool { hasPostEventAccess }

    func sendPasteShortcut() -> Bool {
        sendCount += 1
        onSend()
        return true
    }
}

@MainActor
private struct ImmediatePasteSleeper: PasteSleeping {
    func sleep(for interval: TimeInterval) async throws {}
}
