import AppKit
import Foundation

@MainActor
struct HistoryActionHandler {
    let viewModel: HistoryViewModel
    let contentReader: any ClipboardPasteContentReading
    let assetProvider: any ClipboardItemAssetProviding
    let onCopy: ([ClipboardItem]) async -> Bool
    let onPaste: ([ClipboardItem]) -> Void
    let onDismiss: () -> Void
    let onRestoreFocus: () -> Void
    let presentingWindow: () -> NSWindow?
    let imageExportService = ClipboardImageExportService()

    func performPrimaryPasteAction() {
        let items = currentSelectionSnapshot()
        guard !items.isEmpty else { return }
        onPaste(items)
    }

    func performCopyOnlyAction() {
        copySelection(dismissAfterCopy: true)
    }

    func copySelection(dismissAfterCopy: Bool) {
        let items = currentSelectionSnapshot()
        guard !items.isEmpty else { return }

        Task { @MainActor in
            guard await onCopy(items) else { return }
            viewModel.clearSearchAfterCommittedAction()
            if dismissAfterCopy {
                onDismiss()
                onRestoreFocus()
            }
        }
    }

    func jumpToHistorySelection() {
        guard let item = viewModel.selectedItem else { return }
        viewModel.jumpToHistory(for: item)
    }

    func performDetailAction(_ action: HistoryItemAction) {
        performAction(action, items: currentSelectionSnapshot())
    }

    func performContextMenuAction(_ clickedItemID: UUID, _ action: HistoryItemAction) {
        performAction(action, items: viewModel.contextMenuTargetItems(for: clickedItemID))
    }

    func dismissHistoryWindow() {
        viewModel.clearSearchAfterClosingIfNeeded()
        onDismiss()
    }

    func downloadAllImages() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = String(localized: "Select Folder to Save Images")
        openPanel.prompt = String(localized: "Select")

        guard let window = presentingWindow() else { return }
        let imageItems = viewModel.selectedItems.filter {
            ClipboardItemTypeRegistry.supportsImageAssets(for: $0)
        }

        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK, let folderURL = openPanel.url else { return }
            Task {
                await imageExportService.export(
                    imageItems,
                    to: folderURL,
                    contentReader: contentReader
                )
            }
        }
    }

    func copyOCRText(_ text: String) {
        copyPlainText(text)
    }

    func copyPlainText(_ text: String) {
        Task {
            _ = await onCopy([.text(text)])
        }
    }

    private func performAction(_ action: HistoryItemAction, items: [ClipboardItem]) {
        guard !items.isEmpty else { return }

        switch action {
        case .copy:
            Task { @MainActor in
                if await onCopy(items) {
                    viewModel.clearSearchAfterCommittedAction()
                }
            }

        case .openLink:
            guard let url = items.first?.linkPayload?.url else { return }
            NSWorkspace.shared.open(url)

        case .composeEmail:
            guard let url = items.first?.emailPayload?.mailtoURL else { return }
            NSWorkspace.shared.open(url)

        case .jumpToHistory:
            guard let item = items.first else { return }
            viewModel.jumpToHistory(for: item)

        case .saveImage:
            guard let item = items.first else { return }
            saveImage(item)

        case .extractImageText:
            Task {
                guard let item = items.first else { return }
                await viewModel.extractImageText(for: item)
            }

        case .togglePin:
            viewModel.togglePin(for: items)

        case .toggleBookmark:
            viewModel.toggleBookmark(for: items)

        case .delete:
            viewModel.delete(items)
        }
    }

    private func saveImage(_ item: ClipboardItem) {
        let cachedImage =
            viewModel.selectedItem?.id == item.id
            ? (viewModel.previewImage ?? assetProvider.cachedPreviewImage(for: item))
            : assetProvider.cachedPreviewImage(for: item)
        if let cachedImage {
            PasteImageSupport.saveImageToDisk(cachedImage)
            return
        }

        Task { @MainActor in
            guard let image = await assetProvider.loadPreviewImage(for: item) else { return }
            PasteImageSupport.saveImageToDisk(image)
        }
    }

    private func currentSelectionSnapshot() -> [ClipboardItem] {
        let selectedItems = viewModel.selectedItemsInActionOrder
        if !selectedItems.isEmpty {
            return selectedItems
        }
        return viewModel.selectedItem.map { [$0] } ?? []
    }
}

actor ClipboardImageExportService {
    func export(
        _ items: [ClipboardItem],
        to folderURL: URL,
        contentReader: any ClipboardPasteContentReading
    ) async {
        for (index, item) in items.enumerated() {
            guard !Task.isCancelled,
                let sourceData = await contentReader.pasteImageData(for: item),
                let pngData = PasteImageDataEncoder.pngData(from: sourceData)
            else {
                continue
            }

            let paddedNumber = String(format: "%04d", index + 1)
            let fileURL = folderURL.appendingPathComponent("image-\(paddedNumber).png")
            do {
                try pngData.write(to: fileURL, options: .atomic)
            } catch {
                BufferLogger.ui.error(
                    "Failed to save image to \(fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
