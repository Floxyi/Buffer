import SwiftUI

struct HistoryClipboardListPane: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var settings: SettingsManager
    let store: ClipboardStore
    let actionHandler: HistoryActionHandler
    let onScrollOffsetProviderChanged: (((() -> CGFloat)?) -> Void)
    let onScrollOffsetRestorerChanged: ((((CGFloat) -> Void)?) -> Void)

    var body: some View {
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
                    scrollTrigger: Binding(
                        get: { viewModel.scrollTrigger },
                        set: { viewModel.scrollTrigger = $0 }
                    ),
                    store: store,
                    settings: settings,
                    quickPasteBadgeNumberByItemID: viewModel.showsQuickPasteNumbers
                        ? viewModel.quickPasteBadgeNumberByItemID
                        : [:],
                    onCommitSelection: actionHandler.performPrimaryPasteAction,
                    onDismiss: actionHandler.dismissHistoryWindow,
                    selectedIDs: Binding(
                        get: { viewModel.selectedIDs },
                        set: { _ in }
                    ),
                    onSelectSingle: viewModel.selectSingle(_:at:),
                    onSelectPreferredTopItem: viewModel.selectPreferredTopItem,
                    onToggleSelection: viewModel.toggleSelection,
                    onExtendSelectionTo: viewModel.extendSelectionTo,
                    contextMenuActions: viewModel.contextMenuActions,
                    onContextMenuAction: actionHandler.performContextMenuAction,
                    selectionNavigationToken: viewModel.selectionNavigationToken,
                    selectedItemID: viewModel.selectedID,
                    openScrollRequest: viewModel.openListScrollRequest,
                    openScrollRequestToken: viewModel.openListScrollRequestToken,
                    isShowingFullHistory: viewModel.isShowingFullHistory,
                    keyboardScrollRequest: viewModel.keyboardScrollRequest,
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
}
