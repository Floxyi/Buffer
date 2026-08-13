import AppKit

@MainActor
protocol PasteControlling: AnyObject {
    var hasPostEventAccess: Bool { get }

    func applicationTarget(for application: NSRunningApplication?) -> ApplicationTarget?
    func preparePastePlan(for items: [ClipboardItem]) async throws -> PastePlan
    func executePaste(
        _ plan: PastePlan,
        target: ApplicationTarget?,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome
    func copyToClipboard(_ items: [ClipboardItem]) async throws -> PasteboardWriteReceipt
    func cancelPaste()
    func completePastePlan(_ plan: PastePlan)
    func discardPastePlan(_ plan: PastePlan)
    @discardableResult func requestPostEventAccess() -> Bool
    func saveImageToDisk(_ image: NSImage)
}

@MainActor
final class PasteController: PasteControlling {
    private enum Timing {
        static let temporaryAssetCleanupDelay = 60.0
    }

    private let payloadBuilder: PastePayloadBuilder
    private let sessionCoordinator: PasteSessionCoordinator
    private let imageExporter: any PasteTemporaryAssetExporting
    private let payloadWriter: PastePayloadWriting
    private let targetResolver: @MainActor (NSRunningApplication?) -> ApplicationTarget?

    init(
        store: ClipboardStore,
        imageExporter: any PasteTemporaryAssetExporting = PasteImageExporter(),
        payloadWriter: PastePayloadWriting = PasteboardPayloadWriter(),
        focusRestorer: PasteFocusRestoring = PasteFocusRestorer(),
        eventSender: PasteEventSending = PasteEventSender(),
        sleeper: PasteSleeping = SystemPasteSleeper(),
        targetResolver: (@MainActor (NSRunningApplication?) -> ApplicationTarget?)? = nil
    ) {
        self.payloadBuilder = PastePayloadBuilder(contentReader: store, imageExporter: imageExporter)
        self.payloadWriter = payloadWriter
        self.imageExporter = imageExporter
        self.targetResolver = targetResolver ?? Self.makeApplicationTarget
        self.sessionCoordinator = PasteSessionCoordinator(
            payloadWriter: payloadWriter,
            focusRestorer: focusRestorer,
            eventSender: eventSender,
            sleeper: sleeper
        )

        Task {
            await imageExporter.removeStalePasteSessions()
        }
    }

    var hasPostEventAccess: Bool {
        sessionCoordinator.hasPostEventAccess
    }

    func applicationTarget(for application: NSRunningApplication?) -> ApplicationTarget? {
        targetResolver(application)
    }

    func preparePastePlan(for items: [ClipboardItem]) async throws -> PastePlan {
        try await payloadBuilder.makePastePlan(for: items)
    }

    func executePaste(
        _ plan: PastePlan,
        target: ApplicationTarget?,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome {
        await sessionCoordinator.execute(
            plan,
            target: target,
            suppressCapture: suppressCapture
        )
    }

    func copyToClipboard(_ items: [ClipboardItem]) async throws -> PasteboardWriteReceipt {
        let preparation = try await payloadBuilder.prepareCopyPayload(for: items)
        do {
            let receipt = try payloadWriter.write(preparation.payload)
            scheduleCleanup(for: preparation.temporaryAssetSessionID)
            return receipt
        } catch {
            await removeTemporaryAssets(for: preparation.temporaryAssetSessionID)
            throw error
        }
    }

    func cancelPaste() {
        sessionCoordinator.cancel()
    }

    func completePastePlan(_ plan: PastePlan) {
        scheduleCleanup(for: plan.temporaryAssetSessionID)
    }

    func discardPastePlan(_ plan: PastePlan) {
        guard let sessionID = plan.temporaryAssetSessionID else { return }
        Task {
            await imageExporter.removePasteSession(sessionID)
        }
    }

    @discardableResult
    func requestPostEventAccess() -> Bool {
        sessionCoordinator.requestPostEventAccess()
    }

    func saveImageToDisk(_ image: NSImage) {
        PasteImageSupport.saveImageToDisk(image)
    }

    private func scheduleCleanup(for sessionID: UUID?) {
        guard let sessionID else { return }
        let imageExporter = imageExporter
        Task {
            try? await Task.sleep(
                nanoseconds: UInt64(Timing.temporaryAssetCleanupDelay * 1_000_000_000)
            )
            await imageExporter.removePasteSession(sessionID)
        }
    }

    private func removeTemporaryAssets(for sessionID: UUID?) async {
        guard let sessionID else { return }
        await imageExporter.removePasteSession(sessionID)
    }

    private static func makeApplicationTarget(
        for application: NSRunningApplication?
    ) -> ApplicationTarget? {
        guard let application, !application.isTerminated else { return nil }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }

        let processIdentifier = application.processIdentifier
        return ApplicationTarget(
            processIdentifier: processIdentifier,
            applicationName: application.localizedName ?? "the destination application",
            activate: {
                guard !application.isTerminated else { return }
                application.activate(options: .activateIgnoringOtherApps)
            },
            isReady: {
                guard !application.isTerminated, application.isActive else { return false }
                return NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
            },
            isTerminated: { application.isTerminated }
        )
    }
}
