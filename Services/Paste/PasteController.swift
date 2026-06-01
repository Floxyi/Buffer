import AppKit

@MainActor
protocol PasteControlling: AnyObject {
    func copyToClipboard(_ item: ClipboardItem)
    func copyMultipleToClipboard(_ items: [ClipboardItem])
    func paste(_ item: ClipboardItem, previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void)
    func pasteMultiple(_ items: [ClipboardItem], previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void)
    func saveImageToDisk(_ image: NSImage)
}

@MainActor
final class PasteController: PasteControlling {
    private let payloadBuilder: PastePayloadBuilder
    private let sessionCoordinator: PasteSessionCoordinator
    private let imageExporter: PasteImageExporting
    private let payloadWriter: PastePayloadWriting

    init(
        store: ClipboardStore,
        automation: PasteAutomating = PasteAutomation(),
        imageExporter: PasteImageExporting = PasteImageExporter(),
        payloadWriter: PastePayloadWriting = PasteboardPayloadWriter(),
        scheduler: PasteScheduling = PasteScheduler()
    ) {
        self.payloadBuilder = PastePayloadBuilder(store: store, imageExporter: imageExporter)
        self.payloadWriter = payloadWriter
        self.sessionCoordinator = PasteSessionCoordinator(
            payloadWriter: payloadWriter,
            automation: automation,
            scheduler: scheduler
        )
        self.imageExporter = imageExporter
    }

    func copyToClipboard(_ item: ClipboardItem) {
        guard let payload = payloadBuilder.copyPayload(for: item) else { return }
        payloadWriter.write(payload)
    }

    func copyMultipleToClipboard(_ items: [ClipboardItem]) {
        guard let payload = payloadBuilder.copyPayload(for: items) else { return }
        PasteboardPayloadWriter().write(payload)
    }

    func paste(_ item: ClipboardItem, previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void) {
        sessionCoordinator.paste(
            payload: payloadBuilder.pastePayload(for: item),
            activatePreviousApp: activation(previousApp),
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }

    func pasteMultiple(_ items: [ClipboardItem], previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void) {
        sessionCoordinator.pasteMultiple(
            batch: payloadBuilder.batchPayload(for: items),
            activatePreviousApp: activation(previousApp),
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }

    func saveImageToDisk(_ image: NSImage) {
        imageExporter.saveImageToDisk(image)
    }

    private func activation(_ previousApp: NSRunningApplication?) -> (() -> Void)? {
        guard let previousApp else { return nil }
        return {
            previousApp.activate(options: .activateIgnoringOtherApps)
        }
    }
}
