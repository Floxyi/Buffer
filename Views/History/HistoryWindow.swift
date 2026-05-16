import SwiftUI

struct HistoryContentView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    let store: ClipboardStore
    let onCopyToClipboard: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onPasteMultiple: ([ClipboardItem]) -> Void
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
                }
            }

            BufferPanelSeparator()

            HistoryActionBar(
                showsSaveShortcut: viewModel.selectedItem?.type == .image,
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
                onEscape: onDismiss,
                onDelete: viewModel.deleteSelectedItem,
                onCopy: {
                    if let item = viewModel.selectedItem {
                        onCopyToClipboard(item)
                    }
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
                    quickPasteBadgeNumberByItemID: viewModel.showsQuickPasteNumbers
                        ? viewModel.quickPasteBadgeNumberByItemID
                        : [:],
                    onCommitSelection: performPrimaryPasteAction,
                    onDismiss: onDismiss,
                    selectedIDs: Binding(
                        get: { viewModel.selectedIDs },
                        set: { _ in }
                    ),
                    hoveredItemID: $viewModel.hoveredItemID,
                    onSelectSingle: viewModel.selectSingle,
                    onSelectPreferredTopItem: viewModel.selectPreferredTopItem,
                    onToggleSelection: viewModel.toggleSelection,
                    onExtendSelectionTo: viewModel.extendSelectionTo,
                    onCopyItem: { item in
                        onCopyToClipboard(item)
                    },
                    onTogglePinItem: { item in
                        viewModel.togglePin(for: item)
                    },
                    onDeleteItem: { item in
                        viewModel.delete(item)
                    },
                    onJumpToHistoryItem: viewModel.canJumpToHistorySelection ? { item in
                        viewModel.jumpToHistory(for: item)
                    } : nil,
                    showsJumpToHistoryAction: viewModel.canJumpToHistorySelection,
                    selectionNavigationToken: viewModel.selectionNavigationToken,
                    selectedItemID: viewModel.selectedID,
                    openScrollRequest: viewModel.openListScrollRequest,
                    openScrollRequestToken: viewModel.openListScrollRequestToken,
                    isShowingFullHistory: viewModel.isShowingFullHistory,
                    jumpScrollRequest: viewModel.activeJumpToHistoryRequest,
                    onJumpScrollStarted: viewModel.markJumpToHistoryScrollStarted,
                    onJumpScrollCompleted: viewModel.completeJumpToHistoryScroll,
                    onScrollOffsetChanged: viewModel.updateLastListScrollOffset
                )
            }
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.34)
        }
    }

    private var detailPane: some View {
        HistoryDetailPane(
            selectionCount: viewModel.selectionCount,
            isSingleImageSelection: viewModel.isSingleImageSelection,
            selectedItemIsPinned: viewModel.selectedItemIsPinned,
            canExtractSelectedImageText: viewModel.canExtractSelectedImageText,
            isExtractingText: viewModel.isExtractingText,
            showsJumpToHistory: viewModel.canJumpToHistorySelection,
            selectedItemSourceName: viewModel.selectedItemSourceName,
            selectedItemCopiedAtText: viewModel.selectedItemCopiedAtText,
            selectedItemsTotalSizeText: viewModel.selectedItemsTotalSizeText,
            textSelectionCount: viewModel.textSelectionCount,
            imageSelectionCount: viewModel.imageSelectionCount,
            firstTextPreview: viewModel.firstTextPreview,
            selectedItem: viewModel.selectedItem,
            previewImage: viewModel.previewImage,
            chunkedText: viewModel.chunkedText,
            textDetailFontStyle: settings.textDetailFontStyle,
            textDetailFontSize: settings.textDetailFontSize,
            onCopy: {
                if let item = viewModel.selectedItem {
                    onCopyToClipboard(item)
                }
            },
            onSaveImage: {
                guard let item = viewModel.selectedItem,
                      let image = viewModel.previewImage ?? store.image(for: item) else { return }

                PasteImageSupport.saveImageToDisk(image)
            },
            onExtractText: {
                Task {
                    await viewModel.extractSelectedImageText()
                }
            },
            onJumpToHistory: jumpToHistorySelection,
            onTogglePin: viewModel.togglePinForSelectedItem,
            onDelete: viewModel.deleteSelectedItem,
            onDownloadAllImages: downloadAllImages,
            onCopyOCRText: copyOCRText,
            onLoadNextChunk: { _ in
                Task {
                    await viewModel.loadNextChunk()
                }
            }
        )
    }

    private func performPrimaryPasteAction() {
        viewModel.clearSearchAfterCommittedAction()

        if !viewModel.selectedItems.isEmpty {
            onPasteMultiple(viewModel.selectedItems)
        } else if let item = viewModel.selectedItem {
            onPaste(item)
        }
    }

    private func performCopyOnlyAction() {
        guard let item = viewModel.selectedItem else { return }

        viewModel.clearSearchAfterCommittedAction()
        onCopyToClipboard(item)
        onDismiss()
    }

    private func jumpToHistorySelection() {
        guard let item = viewModel.selectedItem else { return }

        viewModel.jumpToHistory(for: item)
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

            let imageItems = self.viewModel.selectedItems.filter { $0.type == .image }

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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
