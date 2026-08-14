import AppKit
import SwiftUI

struct HistoryContentView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    @ObservedObject var pasteState: HistoryPasteStateController
    let contentReader: any ClipboardPasteContentReading
    let itemAssetProvider: any ClipboardItemAssetProviding
    let listAssetPrewarmer: ClipboardListAssetPrewarmer
    let keyboardScrollRouter: HistoryKeyboardScrollRouter
    let onCopy: ([ClipboardItem]) async -> Bool
    let onPaste: ([ClipboardItem]) -> Void
    let presentingWindow: () -> NSWindow?
    let onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void)
    let onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)
    let onDismiss: () -> Void
    let onRestoreFocus: () -> Void

    @StateObject private var searchFocusController = HistorySearchFocusController()
    @StateObject private var deleteConfirmationController = HistoryDeleteConfirmationController()

    var body: some View {
        content
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
            .allowsHitTesting(!pasteState.isPasteInProgress)
            .alert(item: $viewModel.mutationFailure) { failure in
                Alert(
                    title: Text("Couldn’t Update History"),
                    message: Text(failure.message),
                    dismissButton: .default(Text("OK"), action: viewModel.dismissMutationFailure)
                )
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HistorySearchBar(
                searchText: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                filteredItemCount: viewModel.filteredItems.count,
                isSearchFocused: $searchFocusController.isSearchFocused,
                searchSelectionToken: viewModel.searchSelectionToken,
                filterState: viewModel.filterState,
                applicationOptions: viewModel.applicationFilterOptions,
                onSetBookmarkedOnly: { viewModel.setBookmarkedOnly($0) },
                onSelectApplication: { viewModel.setSelectedApplication(bundleIdentifier: $0) },
                onSelectKind: { viewModel.setSelectedKind($0) },
                onSelectDatePreset: { viewModel.setDateFilterPreset($0) }
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
                showsBookmarkedShortcutAsRemove: viewModel.detailViewState.selectedItemIsBookmarked,
                showsPinnedShortcutAsUnpin: viewModel.detailViewState.selectedItemIsPinned,
                showsSaveShortcut: viewModel.detailViewState.canSaveSelectedImage,
                onPaste: actionHandler.performPrimaryPasteAction
            )
        }
    }

    private func handleKeyboardCommand(_ command: HistoryKeyboardCommand) {
        guard !pasteState.blocksPasteAttempt else { return }
        keyboardCommandHandler.handle(command)
    }

    private var listPane: some View {
        HistoryClipboardListPane(
            viewModel: viewModel,
            settings: settings,
            assetProvider: itemAssetProvider,
            assetPrewarmer: listAssetPrewarmer,
            keyboardScrollRouter: keyboardScrollRouter,
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
            showsSpacesAndTabs: settings.clipboardWhitespaceMode.showsSpacesAndTabs,
            enableWebsitePreviews: settings.enableWebsitePreviews,
            assetProvider: itemAssetProvider,
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
            contentReader: contentReader,
            assetProvider: itemAssetProvider,
            onCopy: onCopy,
            onPaste: onPaste,
            onDismiss: onDismiss,
            onRestoreFocus: onRestoreFocus,
            presentingWindow: presentingWindow
        )
    }

    private var keyboardCommandHandler: HistoryKeyboardCommandHandler {
        HistoryKeyboardCommandHandler(
            isDeleteConfirmationPresenting: deleteConfirmationController.isPresenting,
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
                commitSelection: actionHandler.performPrimaryPasteAction,
                dismiss: actionHandler.dismissHistoryWindow,
                selectAll: viewModel.selectAllItems,
                makeDeleteRequest: viewModel.makeDeleteSelectionRequest,
                deleteSelection: viewModel.delete,
                copySelection: {
                    actionHandler.performCopyOnlyAction()
                },
                toggleBookmark: viewModel.toggleBookmarkForSelectedItem,
                togglePinned: viewModel.togglePinForSelectedItem,
                saveImage: {
                    actionHandler.performDetailAction(.saveImage)
                },
                quickPaste: { index in
                    if let item = viewModel.performQuickPaste(at: index) {
                        onPaste([item])
                    }
                },
                presentDeleteConfirmation: { request in
                    deleteConfirmationController.presentDeleteConfirmation(selectionCount: request.selectionCount) {
                        viewModel.delete(request)
                    }
                }
            )
        )
    }
}
