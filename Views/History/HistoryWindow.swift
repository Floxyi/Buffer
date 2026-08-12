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

    @StateObject private var searchFocusController = HistorySearchFocusController()
    @StateObject private var deleteConfirmationController = HistoryDeleteConfirmationController()

    var body: some View {
        VStack(spacing: 0) {
            HistorySearchBar(
                searchText: $viewModel.searchText,
                filteredItemCount: viewModel.filteredItems.count,
                isSearchFocused: $searchFocusController.isSearchFocused,
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
                showsPinnedShortcutAsUnpin: viewModel.detailViewState.selectedItemIsPinned,
                showsSaveShortcut: viewModel.detailViewState.canSaveSelectedImage,
                showsJumpToHistory: viewModel.detailViewState.canJumpToHistorySelection,
                onJumpToHistory: actionHandler.jumpToHistorySelection,
                onPaste: actionHandler.performPrimaryPasteAction
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
            searchFocusController.handleAppear(isAppActive: NSApp.isActive)
        }
        .onChange(of: viewModel.windowOpenToken) { _ in
            searchFocusController.handleWindowOpen(shouldFocusSearch: viewModel.shouldFocusSearchOnOpen)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            searchFocusController.handleDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            viewModel.handleAppResignActive()
        }
        .background(
            HistoryWindowKeyMonitor(
                onCommand: handleKeyboardCommand(_:)
            )
        )
    }

    private func handleKeyboardCommand(_ command: HistoryKeyboardCommand) {
        keyboardCommandHandler.handle(command)
    }

    private var listPane: some View {
        HistoryClipboardListPane(
            viewModel: viewModel,
            settings: settings,
            store: store,
            actionHandler: actionHandler,
            onScrollOffsetProviderChanged: onScrollOffsetProviderChanged,
            onScrollOffsetRestorerChanged: onScrollOffsetRestorerChanged
        )
    }

    private var detailPane: some View {
            HistoryDetailPane(
                detailState: viewModel.detailViewState,
                textDetailFontStyle: settings.textDetailFontStyle,
                textDetailFontSize: settings.textDetailFontSize,
                enableWebsitePreviews: settings.enableWebsitePreviews,
                store: store,
                actionsForItem: { item in
                    viewModel.contextMenuActions(for: item.id)
                },
                onSelectItemAction: { item, action in
                    actionHandler.performContextMenuAction(item.id, action)
                },
                onSelectAction: actionHandler.performDetailAction,
                onDownloadAllImages: actionHandler.downloadAllImages,
                onCopyOCRText: actionHandler.copyOCRText,
                onCopyColorVariant: actionHandler.copyPlainText,
                onLoadNextChunk: { _ in
                    Task {
                        await viewModel.loadNextChunk()
                    }
                }
            )
    }

    private var actionHandler: HistoryActionHandler {
        HistoryActionHandler(
            viewModel: viewModel,
            store: store,
            onCopyToClipboard: onCopyToClipboard,
            onCopyMultipleToClipboard: onCopyMultipleToClipboard,
            onPaste: onPaste,
            onPasteMultiple: onPasteMultiple,
            onDismiss: onDismiss
        )
    }

    private var keyboardCommandHandler: HistoryKeyboardCommandHandler {
        HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: deleteConfirmationController.isPresenting,
            selectionCount: viewModel.selectionCount,
            confirmDeleteWithKeyboardShortcut: settings.confirmDeleteWithKeyboardShortcut,
            actions: .init(
                handleModifierFlagsChange: viewModel.handleQuickPasteModifierFlagsChange,
                moveUp: { extendSelection in
                    extendSelection ? viewModel.extendSelectionUp() : viewModel.navigateUp()
                },
                moveDown: { extendSelection in
                    extendSelection ? viewModel.extendSelectionDown() : viewModel.navigateDown()
                },
                moveToFirst: { extendSelection in
                    extendSelection ? viewModel.extendSelectionToFirstItem() : viewModel.jumpToFirstItem()
                },
                moveToLast: { extendSelection in
                    extendSelection ? viewModel.extendSelectionToLastItem() : viewModel.jumpToLastItem()
                },
                commitSelection: { copyOnly in
                    copyOnly ? actionHandler.performCopyOnlyAction() : actionHandler.performPrimaryPasteAction()
                },
                dismiss: actionHandler.dismissHistoryWindow,
                deleteSelection: viewModel.deleteSelectedItem,
                copySelection: {
                    actionHandler.copySelection(dismissAfterCopy: false)
                },
                togglePinned: viewModel.togglePinForSelectedItem,
                saveImage: {
                    if let image = viewModel.detailViewState.previewImage {
                        PasteImageSupport.saveImageToDisk(image)
                    }
                },
                quickPaste: { index in
                    if let item = viewModel.performQuickPaste(at: index) {
                        onPaste(item)
                    }
                },
                presentDeleteConfirmation: { selectionCount in
                    deleteConfirmationController.presentDeleteConfirmation(selectionCount: selectionCount) {
                        viewModel.deleteSelectedItem()
                    }
                }
            )
        )
    }
}
