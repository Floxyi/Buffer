import Foundation

@MainActor
struct ApplicationTarget {
    let processIdentifier: pid_t
    let applicationName: String
    let activate: () -> Void
    let isReady: () -> Bool
    let isTerminated: () -> Bool
}

enum PasteFailure: LocalizedError, Equatable {
    case missingDestination
    case destinationTerminated
    case eventPermissionDenied
    case focusTimeout
    case pasteboardWrite(String)
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .missingDestination:
            String(localized: "Buffer could not determine which application should receive the paste.")
        case .destinationTerminated:
            String(localized: "The destination application is no longer running.")
        case .eventPermissionDenied:
            String(
                localized:
                    "Enable Buffer in Accessibility settings, return to the application you want to paste into, then open Buffer again."
            )
        case .focusTimeout:
            String(localized: "The destination application did not regain keyboard focus in time.")
        case .pasteboardWrite(let message):
            message
        case .eventCreationFailed:
            String(localized: "Buffer could not send the paste shortcut.")
        }
    }
}

enum PasteOutcome {
    case success
    case cancelled
    case failure(PasteFailure, remainingPlan: PastePlan, completedStepCount: Int)
}

@MainActor
protocol PasteSleeping {
    func sleep(for interval: TimeInterval) async throws
}

struct SystemPasteSleeper: PasteSleeping {
    func sleep(for interval: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: interval.nanoseconds)
    }
}

@MainActor
protocol PasteFocusRestoring {
    func restoreFocus(to target: ApplicationTarget) async -> Bool
}

@MainActor
final class PasteFocusRestorer: PasteFocusRestoring {
    private enum Timing {
        static let pollInterval = 0.025
        static let timeout = 2.0
    }

    private let sleeper: PasteSleeping

    init(sleeper: PasteSleeping = SystemPasteSleeper()) {
        self.sleeper = sleeper
    }

    func restoreFocus(to target: ApplicationTarget) async -> Bool {
        guard !target.isTerminated() else { return false }
        if target.isReady() { return true }

        target.activate()
        let attemptCount = Int(Timing.timeout / Timing.pollInterval)
        for _ in 0..<attemptCount {
            do {
                try await sleeper.sleep(for: Timing.pollInterval)
            } catch {
                return false
            }

            guard !target.isTerminated() else { return false }
            if target.isReady() { return true }
        }
        return false
    }
}

@MainActor
final class PasteSessionCoordinator {
    private let payloadWriter: PastePayloadWriting
    private let focusRestorer: PasteFocusRestoring
    private let eventSender: PasteEventSending
    private let sleeper: PasteSleeping

    private var generation = 0
    private var activeTask: Task<PasteOutcome, Never>?

    init(
        payloadWriter: PastePayloadWriting,
        focusRestorer: PasteFocusRestoring = PasteFocusRestorer(),
        eventSender: PasteEventSending = PasteEventSender(),
        sleeper: PasteSleeping = SystemPasteSleeper()
    ) {
        self.payloadWriter = payloadWriter
        self.focusRestorer = focusRestorer
        self.eventSender = eventSender
        self.sleeper = sleeper
    }

    var hasPostEventAccess: Bool {
        eventSender.hasPostEventAccess
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        eventSender.requestPostEventAccess()
    }

    func execute(
        _ plan: PastePlan,
        target: ApplicationTarget?,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome {
        cancel()
        generation &+= 1
        let generation = generation

        guard let target else {
            return .failure(
                .missingDestination,
                remainingPlan: plan,
                completedStepCount: 0
            )
        }
        guard !target.isTerminated() else {
            return .failure(
                .destinationTerminated,
                remainingPlan: plan,
                completedStepCount: 0
            )
        }
        guard eventSender.hasPostEventAccess else {
            return .failure(
                .eventPermissionDenied,
                remainingPlan: plan,
                completedStepCount: 0
            )
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return PasteOutcome.cancelled }
            return await self.run(
                plan,
                target: target,
                generation: generation,
                suppressCapture: suppressCapture
            )
        }
        activeTask = task
        let outcome = await task.value
        if self.generation == generation {
            activeTask = nil
        }
        return outcome
    }

    func cancel() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
    }

    private func run(
        _ plan: PastePlan,
        target: ApplicationTarget,
        generation: Int,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome {
        let token = BufferPerformanceDiagnostics.begin(.pasteSession)
        defer { BufferPerformanceDiagnostics.end(token) }

        for (index, step) in plan.steps.enumerated() {
            guard isCurrent(generation) else { return .cancelled }

            if step.delayBeforeExecution > 0 {
                do {
                    try await sleeper.sleep(for: step.delayBeforeExecution)
                } catch {
                    return .cancelled
                }
            }

            guard isCurrent(generation) else { return .cancelled }
            guard !target.isTerminated() else {
                return failure(
                    .destinationTerminated,
                    plan: plan,
                    failedStepIndex: index
                )
            }
            guard await focusRestorer.restoreFocus(to: target) else {
                if Task.isCancelled { return .cancelled }
                return failure(.focusTimeout, plan: plan, failedStepIndex: index)
            }
            guard isCurrent(generation) else { return .cancelled }

            let receipt: PasteboardWriteReceipt
            do {
                receipt = try payloadWriter.write(step.payload)
            } catch {
                return failure(
                    .pasteboardWrite(error.localizedDescription),
                    plan: plan,
                    failedStepIndex: index
                )
            }
            suppressCapture(receipt)

            guard eventSender.sendPasteShortcut() else {
                let reason: PasteFailure =
                    eventSender.hasPostEventAccess
                    ? .eventCreationFailed
                    : .eventPermissionDenied
                return failure(reason, plan: plan, failedStepIndex: index)
            }
        }

        return .success
    }

    private func failure(
        _ failure: PasteFailure,
        plan: PastePlan,
        failedStepIndex: Int
    ) -> PasteOutcome {
        guard let remainingPlan = plan.remainingSteps(startingAt: failedStepIndex) else {
            return .cancelled
        }
        return .failure(
            failure,
            remainingPlan: remainingPlan,
            completedStepCount: plan.completedStepCount + failedStepIndex
        )
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && self.generation == generation
    }
}

extension TimeInterval {
    fileprivate var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
