import AppKit

@MainActor
protocol PasteControlling: AnyObject {
    func copyToClipboard(_ item: ClipboardItem)
    func paste(_ item: ClipboardItem, previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void)
    func pasteMultiple(_ items: [ClipboardItem], previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void)
    func saveImageToDisk(_ image: NSImage)
}

@MainActor
final class PasteController: PasteControlling {
    private let store: ClipboardStore
    private let automation: PasteAutomating

    init(store: ClipboardStore, automation: PasteAutomating = PasteAutomation()) {
        self.store = store
        self.automation = automation
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item), let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
        }
    }

    func paste(_ item: ClipboardItem, previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            if let text = store.fullText(for: item) {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let image = store.image(for: item) {
                if let fileURL = PasteImageSupport.saveImageToTemp(image, fileName: "image-0001.png") {
                    pasteboard.writeObjects([fileURL as NSPasteboardWriting])
                } else if let tiffData = image.tiffRepresentation {
                    pasteboard.setData(tiffData, forType: .tiff)
                }
            }
        }

        ignoreNextCapturedChange()
        previousApp?.activate(options: .activateIgnoringOtherApps)
        automation.simulatePaste(after: 0.1)
    }

    func pasteMultiple(_ items: [ClipboardItem], previousApp: NSRunningApplication?, ignoreNextCapturedChange: @escaping @MainActor () -> Void) {
        guard !items.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let textItems = items.filter { $0.type == .text }
        let imageItems = items.filter { $0.type == .image }

        if !textItems.isEmpty {
            pasteboard.clearContents()
            let joinedText = textItems.compactMap { store.fullText(for: $0) }.joined(separator: "\n")
            pasteboard.setString(joinedText, forType: .string)

            ignoreNextCapturedChange()
            previousApp?.activate(options: .activateIgnoringOtherApps)
            automation.simulatePaste(after: 0.1)

            guard !imageItems.isEmpty else { return }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.pasteImages(imageItems, previousApp: nil, ignoreNextCapturedChange: ignoreNextCapturedChange)
            }
        } else if !imageItems.isEmpty {
            previousApp?.activate(options: .activateIgnoringOtherApps)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self.pasteImages(imageItems, previousApp: nil, ignoreNextCapturedChange: ignoreNextCapturedChange)
            }
        }
    }

    func saveImageToDisk(_ image: NSImage) {
        PasteImageSupport.saveImageToDisk(image)
    }

    private func pasteImages(
        _ items: [ClipboardItem],
        previousApp: NSRunningApplication?,
        ignoreNextCapturedChange: @escaping @MainActor () -> Void
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let imageURLs = items.enumerated().compactMap { index, item -> URL? in
            guard let image = store.image(for: item) else { return nil }
            let paddedNumber = String(format: "%04d", index + 1)
            return PasteImageSupport.saveImageToTemp(image, fileName: "image-\(paddedNumber).png")
        }

        guard !imageURLs.isEmpty else { return }

        ignoreNextCapturedChange()
        previousApp?.activate(options: .activateIgnoringOtherApps)
        pasteboard.writeObjects(imageURLs as [NSPasteboardWriting])
        automation.simulatePaste(after: 0.05)
    }
}
