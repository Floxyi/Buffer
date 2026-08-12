import AppKit
import Foundation

@MainActor
struct HistoryActionHandler {
    let viewModel: HistoryViewModel
    let store: ClipboardStore
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onCopyMultipleToClipboard: ([ClipboardItem]) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onPasteMultiple: ([ClipboardItem]) -> Void
    let onDismiss: () -> Void

    func performPrimaryPasteAction() {
        performCommittedSelectionAction(
            onSingle: onPaste,
            onMultiple: onPasteMultiple
        )
    }

    func performCopyOnlyAction() {
        copySelection(dismissAfterCopy: true)
    }

    func copySelection(dismissAfterCopy: Bool) {
        guard
            performCommittedSelectionAction(
                onSingle: onCopyToClipboard,
                onMultiple: onCopyMultipleToClipboard
            )
        else { return }

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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func performAction(_ action: HistoryItemAction, items: [ClipboardItem]) {
        guard !items.isEmpty else { return }

        switch action {
        case .copy:
            performCommittedAction(
                with: items,
                onSingle: onCopyToClipboard,
                onMultiple: onCopyMultipleToClipboard
            )

        case .openLink:
            guard let url = items.first?.linkPayload?.url else { return }
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

    @discardableResult
    private func performCommittedSelectionAction(
        onSingle: (ClipboardItem) -> Void,
        onMultiple: ([ClipboardItem]) -> Void
    ) -> Bool {
        performCommittedAction(
            with: currentSelectionSnapshot(),
            onSingle: onSingle,
            onMultiple: onMultiple
        )
    }

    @discardableResult
    private func performCommittedAction(
        with items: [ClipboardItem],
        onSingle: (ClipboardItem) -> Void,
        onMultiple: ([ClipboardItem]) -> Void
    ) -> Bool {
        guard !items.isEmpty else { return false }

        // Clearing search rebuilds the visible list and may change selection. Keep the
        // immutable action targets captured above authoritative for this commit.
        viewModel.clearSearchAfterCommittedAction()

        if items.count == 1 {
            onSingle(items[0])
        } else {
            onMultiple(items)
        }
        return true
    }

    private func currentSelectionSnapshot() -> [ClipboardItem] {
        let selectedItems = viewModel.selectedItemsInActionOrder
        if !selectedItems.isEmpty {
            return selectedItems
        }
        return viewModel.selectedItem.map { [$0] } ?? []
    }
}
