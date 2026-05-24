import SwiftUI

struct HistoryImageDetailHeader: View {
    let sourceAppName: String?
    let copiedAtText: String?
    let actions: [HistoryItemActionDescriptor]
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistoryDetailHeaderMetadata(
                    sourceAppName: sourceAppName,
                    copiedAtText: copiedAtText
                )
            },
            actions: {
                HistoryDetailHeaderActionButtons(actions: actions, onSelect: onSelectAction)
            }
        )
    }
}
