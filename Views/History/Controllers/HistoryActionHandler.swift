import AppKit
import Foundation

@MainActor
struct HistoryActionHandler {
    let viewModel: HistoryViewModel
    let store: ClipboardStore
    let onCopyToClipboard: (ClipboardItem) -> Bool
    let onCopyMultipleToClipboard: ([ClipboardItem]) -> Bool
    let onPaste: (ClipboardItem) -> Void
    let onPasteMultiple: ([ClipboardItem]) -> Void
    let onDismiss: () -> Void

    func performPrimaryPasteAction() {
        performSelectionAction(
            onSingle: onPaste,
            onMultiple: onPasteMultiple
        )
    }

    func performCopyOnlyAction() {
        copySelection(dismissAfterCopy: true)
    }

    func copySelection(dismissAfterCopy: Bool) {
        let items = currentSelectionSnapshot()
        guard performCopyAction(with: items) else { return }

        viewModel.clearSearchAfterCommittedAction()
        if dismissAfterCopy {
            onDismiss()
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
        openPanel.title = "Select Folder to Save Images"
        openPanel.prompt = "Select"

        guard let window = NSApplication.shared.windows.first else { return }

        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK, let folderURL = openPanel.url else { return }

            let imageItems = self.viewModel.selectedItems.filter {
                ClipboardItemTypeRegistry.supportsImageAssets(for: $0)
            }

            for (index, item) in imageItems.enumerated() {
                guard let image = self.store.image(for: item) else { continue }

                let paddedNumber = String(format: "%04d", index + 1)
                let fileURL = folderURL.appendingPathComponent("image-\(paddedNumber).png")

                guard let tiffData = image.tiffRepresentation,
                    let bitmapImage = NSBitmapImageRep(data: tiffData),
                    let pngData = bitmapImage.representation(using: .png, properties: [:])
                else {
                    continue
                }

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

    func copyOCRText(_ text: String) {
        copyPlainText(text)
    }

    func copyPlainText(_ text: String) {
        _ = onCopyToClipboard(.text(text))
    }

    private func performAction(_ action: HistoryItemAction, items: [ClipboardItem]) {
        guard !items.isEmpty else { return }

        switch action {
        case .copy:
            if performCopyAction(with: items) {
                viewModel.clearSearchAfterCommittedAction()
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
            let image =
                viewModel.selectedItem?.id == item.id
                ? (viewModel.previewImage ?? store.image(for: item))
                : store.image(for: item)
            guard let image else { return }
            PasteImageSupport.saveImageToDisk(image)

        case .extractImageText:
            Task {
                guard let item = items.first else { return }
                await viewModel.extractImageText(for: item)
            }

        case .togglePin:
            if items.count == 1, let item = items.first {
                viewModel.togglePin(for: item)
            } else if let clickedID = items.first?.id {
                viewModel.togglePinForContextMenuTarget(clickedID)
            }

        case .delete:
            if items.count == 1, let item = items.first {
                viewModel.delete(item)
            } else if let clickedID = items.first?.id {
                viewModel.deleteContextMenuTarget(clickedID)
            }
        }
    }

    private func performSelectionAction(
        onSingle: (ClipboardItem) -> Void,
        onMultiple: ([ClipboardItem]) -> Void
    ) {
        let items = currentSelectionSnapshot()
        guard !items.isEmpty else { return }

        if items.count == 1 {
            onSingle(items[0])
        } else {
            onMultiple(items)
        }
    }

    private func performCopyAction(with items: [ClipboardItem]) -> Bool {
        guard !items.isEmpty else { return false }

        if items.count == 1 {
            return onCopyToClipboard(items[0])
        }
        return onCopyMultipleToClipboard(items)
    }

    private func currentSelectionSnapshot() -> [ClipboardItem] {
        let selectedItems = viewModel.selectedItemsInActionOrder
        if !selectedItems.isEmpty {
            return selectedItems
        }
        return viewModel.selectedItem.map { [$0] } ?? []
    }
}
