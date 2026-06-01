import Foundation

@MainActor
final class MainActorOperationBox: @unchecked Sendable {
    private let operation: @MainActor () -> Void

    init(_ operation: @escaping @MainActor () -> Void) {
        self.operation = operation
    }

    func run() {
        operation()
    }
}

protocol PasteScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: MainActorOperationBox
    )
}

struct PasteScheduler: PasteScheduling {
    func schedule(
        after delay: TimeInterval,
        operation: MainActorOperationBox
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                operation.run()
            }
        }
    }
}

@MainActor
final class PasteSessionCoordinator {
    private let payloadWriter: PastePayloadWriting
    private let automation: PasteAutomating
    private let scheduler: PasteScheduling

    init(
        payloadWriter: PastePayloadWriting,
        automation: PasteAutomating,
        scheduler: PasteScheduling = PasteScheduler()
    ) {
        self.payloadWriter = payloadWriter
        self.automation = automation
        self.scheduler = scheduler
    }

    func paste(
        payload: PastePayload?,
        activatePreviousApp: (() -> Void)?,
        ignoreNextCapturedChange: @escaping @MainActor () -> Void
    ) {
        guard let payload else { return }

        payloadWriter.write(payload)
        ignoreNextCapturedChange()
        activatePreviousApp?()
        automation.simulatePaste(after: 0.1)
    }

    func pasteMultiple(
        batch: PasteBatchPayload,
        activatePreviousApp: (() -> Void)?,
        ignoreNextCapturedChange: @escaping @MainActor () -> Void
    ) {
        guard batch.hasContent else { return }

        if let textPayload = batch.textPayload {
            payloadWriter.write(.string(textPayload))
            ignoreNextCapturedChange()
            activatePreviousApp?()
            automation.simulatePaste(after: 0.1)

            guard !batch.imageFileURLs.isEmpty else { return }

            scheduler.schedule(after: 0.5, operation: MainActorOperationBox { [payloadWriter, automation] in
                payloadWriter.write(.fileURLs(batch.imageFileURLs))
                ignoreNextCapturedChange()
                automation.simulatePaste(after: 0.05)
            })
            return
        }

        guard !batch.imageFileURLs.isEmpty else { return }

        activatePreviousApp?()
        scheduler.schedule(after: 0.1, operation: MainActorOperationBox { [payloadWriter, automation] in
            payloadWriter.write(.fileURLs(batch.imageFileURLs))
            ignoreNextCapturedChange()
            automation.simulatePaste(after: 0.05)
        })
    }
}
