import AppKit
import SwiftUI

struct HistoryContentView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    let store: ClipboardStore
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onCopyMultipleToClipboard: ([ClipboardItem]) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onPasteMultiple: ([ClipboardItem]) -> Void
    let onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void)
    let onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)
    let onDismiss: () -> Void

    @State private var isSearchFocused = false
    @State private var shouldRefocusSearchOnActivate = false

    var body: some View {
        VStack(spacing: 0) {
            HistorySearchBar(
                searchText: $viewModel.searchText,
                filteredItemCount: viewModel.filteredItems.count,
                isSearchFocused: $isSearchFocused,
                searchSelectionToken: viewModel.searchSelectionToken
            )

            BufferPanelSeparator()

            HStack(spacing: 0) {
                listPane
                    .frame(minWidth: 300, maxWidth: .infinity)

                BufferPanelSeparator(isVertical: true)

                if viewModel.selectionCount > 0 {
                    detailPane
                        .frame(minWidth: 500, maxWidth: .infinity)
                        .transition(.identity)
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                }
            }

            BufferPanelSeparator()

            HistoryActionBar(
                showsPinnedShortcutAsUnpin: viewModel.selectedItemIsPinned,
                showsSaveShortcut: viewModel.canSaveSelectedImage,
                showsJumpToHistory: viewModel.canJumpToHistorySelection,
                onJumpToHistory: jumpToHistorySelection,
                onPaste: performPrimaryPasteAction
            )
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(BufferWindowBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: HistoryWindowStyle.panelCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: HistoryWindowStyle.panelCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(HistoryWindowStyle.panelBorderOpacity), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 24, y: 10)
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if NSApp.isActive {
                focusSearchField()
            }
        }
        .onChange(of: viewModel.windowOpenToken) { _ in
            if viewModel.shouldFocusSearchOnOpen {
                shouldRefocusSearchOnActivate = true
                focusSearchField()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard shouldRefocusSearchOnActivate else { return }

            focusSearchField()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                shouldRefocusSearchOnActivate = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.handleAppResignActive()
        }
        .task(id: viewModel.selectedItem?.id) {
            await viewModel.loadPreviewIfNeeded()
        }
        .background(
            GlobalKeyMonitor(
                onUp: viewModel.navigateUp,
                onDown: viewModel.navigateDown,
                onJumpToFirst: viewModel.jumpToFirstItem,
                onJumpToLast: viewModel.jumpToLastItem,
                onExtendToFirst: viewModel.extendSelectionToFirstItem,
                onExtendToLast: viewModel.extendSelectionToLastItem,
                onExtendUp: viewModel.extendSelectionUp,
                onExtendDown: viewModel.extendSelectionDown,
                onEnter: performPrimaryPasteAction,
                onOptionEnter: performCopyOnlyAction,
                onEscape: dismissHistoryWindow,
                onDelete: viewModel.deleteSelectedItem,
                onCopy: {
                    copySelection(dismissAfterCopy: false)
                },
                onPin: viewModel.togglePinForSelectedItem,
                onSaveImage: {
                    if let image = viewModel.previewImage {
                        PasteImageSupport.saveImageToDisk(image)
                    }
                },
                onQuickPaste: { index in
                    if let item = viewModel.performQuickPaste(at: index) {
                        onPaste(item)
                    }
                },
                onCommandChanged: viewModel.handleQuickPasteModifierFlagsChange
            )
        )
    }

    private var listPane: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                Spacer()
            } else {
                ClipboardListView(
                    items: viewModel.filteredItems,
                    selectedIndex: Binding(
                        get: { viewModel.selectedIndex },
                        set: { _ in }
                    ),
                    scrollTrigger: $viewModel.scrollTrigger,
                    store: store,
                    settings: settings,
                    quickPasteBadgeNumberByItemID: viewModel.showsQuickPasteNumbers
                        ? viewModel.quickPasteBadgeNumberByItemID
                        : [:],
                    onCommitSelection: performPrimaryPasteAction,
                    onDismiss: dismissHistoryWindow,
                    selectedIDs: Binding(
                        get: { viewModel.selectedIDs },
                        set: { _ in }
                    ),
                    hoveredItemID: $viewModel.hoveredItemID,
                    onSelectSingle: viewModel.selectSingle,
                    onSelectPreferredTopItem: viewModel.selectPreferredTopItem,
                    onToggleSelection: viewModel.toggleSelection,
                    onExtendSelectionTo: viewModel.extendSelectionTo,
                    contextMenuActions: viewModel.contextMenuActions,
                    onContextMenuAction: performContextMenuAction,
                    selectionNavigationToken: viewModel.selectionNavigationToken,
                    selectedItemID: viewModel.selectedID,
                    openScrollRequest: viewModel.openListScrollRequest,
                    openScrollRequestToken: viewModel.openListScrollRequestToken,
                    isShowingFullHistory: viewModel.isShowingFullHistory,
                    keyboardNavigationRequest: viewModel.keyboardNavigationRequest,
                    onCompleteKeyboardNavigation: viewModel.completeKeyboardNavigation,
                    jumpScrollRequest: viewModel.activeJumpToHistoryRequest,
                    onJumpScrollStarted: viewModel.markJumpToHistoryScrollStarted,
                    onJumpScrollCompleted: viewModel.completeJumpToHistoryScroll,
                    onScrollOffsetProviderChanged: onScrollOffsetProviderChanged,
                    onScrollOffsetRestorerChanged: onScrollOffsetRestorerChanged
                )
            }
        }
        .background {
            HistoryPanelSurfaceBackground()
        }
    }

    private var detailPane: some View {
            HistoryDetailPane(
                selectionCount: viewModel.selectionCount,
                selectedItem: viewModel.selectedItem,
                selectedItems: viewModel.selectedItemsInVisualOrder,
                isExtractingText: viewModel.isExtractingText,
                selectedItemSourceName: viewModel.selectedItemSourceName,
                selectedItemCopiedAtText: viewModel.selectedItemCopiedAtText,
                selectedItemsTotalSizeText: viewModel.selectedItemsTotalSizeText,
                textSelectionCount: viewModel.textSelectionCount,
                imageSelectionCount: viewModel.imageSelectionCount,
                colorSelectionCount: viewModel.colorSelectionCount,
                linkSelectionCount: viewModel.linkSelectionCount,
                firstTextPreview: viewModel.firstTextPreview,
                previewImage: viewModel.previewImage,
                chunkedText: viewModel.chunkedText,
                textDetailFontStyle: settings.textDetailFontStyle,
                textDetailFontSize: settings.textDetailFontSize,
                enableWebsitePreviews: settings.enableWebsitePreviews,
                store: store,
                actions: viewModel.detailActions,
                actionsForItem: { item in
                    viewModel.contextMenuActions(for: item.id)
                },
                onSelectItemAction: { item, action in
                    performAction(action, items: [item])
                },
                onSelectAction: performDetailAction,
                onDownloadAllImages: downloadAllImages,
                onCopyOCRText: copyOCRText,
                onCopyColorVariant: copyPlainText,
                onLoadNextChunk: { _ in
                    Task {
                        await viewModel.loadNextChunk()
                    }
                }
            )
    }

    private func performPrimaryPasteAction() {
        viewModel.clearSearchAfterCommittedAction()

        let items = viewModel.selectedItemsInActionOrder
        if items.count > 1 {
            onPasteMultiple(items)
        } else if let item = items.first ?? viewModel.selectedItem {
            onPaste(item)
        }
    }

    private func performCopyOnlyAction() {
        copySelection(dismissAfterCopy: true)
    }

    private func copySelection(dismissAfterCopy: Bool) {
        let items = viewModel.selectedItemsInActionOrder
        guard !items.isEmpty else { return }

        viewModel.clearSearchAfterCommittedAction()

        if items.count == 1, let item = items.first {
            onCopyToClipboard(item)
        } else {
            onCopyMultipleToClipboard(items)
        }

        if dismissAfterCopy {
            onDismiss()
        }
    }

    private func jumpToHistorySelection() {
        guard let item = viewModel.selectedItem else { return }

        viewModel.jumpToHistory(for: item)
    }

    private func performDetailAction(_ action: HistoryItemAction) {
        performAction(
            action,
            items: viewModel.selectedItemsInActionOrder.isEmpty ? viewModel.selectedItem.map { [$0] } ?? [] : viewModel.selectedItemsInActionOrder
        )
    }

    private func performContextMenuAction(_ clickedItemID: UUID, _ action: HistoryItemAction) {
        performAction(action, items: viewModel.contextMenuTargetItems(for: clickedItemID))
    }

    private func performAction(_ action: HistoryItemAction, items: [ClipboardItem]) {
        guard !items.isEmpty else { return }

        switch action {
        case .copy:
            viewModel.clearSearchAfterCommittedAction()
            if items.count == 1, let item = items.first {
                onCopyToClipboard(item)
            } else {
                onCopyMultipleToClipboard(items)
            }

        case .openLink:
            guard let url = items.first?.linkPayload?.url else { return }
            NSWorkspace.shared.open(url)

        case .jumpToHistory:
            guard let item = items.first else { return }
            viewModel.jumpToHistory(for: item)

        case .saveImage:
            guard let item = items.first else { return }
            let image = viewModel.selectedItem?.id == item.id
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
            } else {
                let targetIDs = Set(items.map(\.id))
                if let clickedID = items.first(where: { targetIDs.contains($0.id) })?.id {
                    viewModel.togglePinForContextMenuTarget(clickedID)
                }
            }

        case .delete:
            if items.count == 1, let item = items.first {
                viewModel.delete(item)
            } else if let clickedID = items.first?.id {
                viewModel.deleteContextMenuTarget(clickedID)
            }
        }
    }

    private func dismissHistoryWindow() {
        viewModel.clearSearchAfterClosingIfNeeded()
        onDismiss()
    }

    private func focusSearchField() {
        isSearchFocused = false

        Task { @MainActor in
            isSearchFocused = true
            try? await Task.sleep(nanoseconds: 50_000_000)
            isSearchFocused = true
            try? await Task.sleep(nanoseconds: 100_000_000)
            isSearchFocused = true
        }
    }

    private func downloadAllImages() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.title = "Select Folder to Save Images"
        openPanel.prompt = "Select"

        guard let window = NSApplication.shared.windows.first else { return }

        openPanel.beginSheetModal(for: window) { response in
            guard response == .OK, let folderURL = openPanel.url else { return }

            let imageItems = self.viewModel.selectedItems.filter { ClipboardItemTypeRegistry.supportsImageAssets(for: $0) }

            for (index, item) in imageItems.enumerated() {
                guard let image = store.image(for: item) else { continue }

                let paddedNumber = String(format: "%04d", index + 1)
                let fileURL = folderURL.appendingPathComponent("image-\(paddedNumber).png")

                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData),
                      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
                    continue
                }

                do {
                    try pngData.write(to: fileURL, options: .atomic)
                } catch {
                    BufferLogger.ui.error("Failed to save image to \(fileURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    private func copyOCRText(_ text: String) {
        copyPlainText(text)
    }

    private func copyPlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
