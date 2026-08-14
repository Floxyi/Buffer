import SwiftUI

struct HistoryClipboardListPane: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    let assetProvider: any ClipboardItemAssetProviding
    let assetPrewarmer: ClipboardListAssetPrewarmer
    let keyboardScrollRouter: HistoryKeyboardScrollRouter
    let actionHandler: HistoryActionHandler
    let onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void)
    let onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)

    var body: some View {
        Group {
            if viewModel.filteredItems.isEmpty {
                Spacer()
            } else {
                ClipboardListView(
                    state: ClipboardListViewState(
                        items: viewModel.filteredItems,
                        itemsSnapshotID: viewModel.filteredItemsSnapshotID,
                        selectedIDs: viewModel.selectedIDs,
                        quickPasteBadgeNumberByItemID: viewModel.showsQuickPasteNumbers
                            ? viewModel.quickPasteBadgeNumberByItemID
                            : [:],
                        searchResultsByItemID: viewModel.searchResultsByItemID,
                        queryText: viewModel.searchText
                    ),
                    navigation: ClipboardListNavigationState(
                        openScrollRequest: viewModel.openListScrollRequest,
                        openScrollRequestToken: viewModel.openListScrollRequestToken,
                        isShowingFullHistory: viewModel.isShowingFullHistory,
                        jumpScrollRequest: viewModel.activeJumpToHistoryRequest
                    ),
                    actions: ClipboardListActions(
                        commitSelection: actionHandler.performPrimaryPasteAction,
                        selectSingle: viewModel.selectSingle(_:at:),
                        selectPreferredTopItem: viewModel.selectPreferredTopItem,
                        toggleSelection: viewModel.toggleSelection,
                        extendSelection: viewModel.extendSelectionTo,
                        contextMenuActions: viewModel.contextMenuActions,
                        performContextMenuAction: actionHandler.performContextMenuAction,
                        jumpScrollStarted: viewModel.markJumpToHistoryScrollStarted,
                        jumpScrollCompleted: viewModel.completeJumpToHistoryScroll,
                        scrollOffsetProviderChanged: onScrollOffsetProviderChanged,
                        scrollOffsetRestorerChanged: onScrollOffsetRestorerChanged
                    ),
                    websitePreviewsEnabled: settings.enableWebsitePreviews,
                    assetProvider: assetProvider,
                    assetPrewarmer: assetPrewarmer,
                    keyboardScrollRouter: keyboardScrollRouter
                )
            }
        }
        .background {
            HistoryPanelSurfaceBackground()
        }
    }
}
