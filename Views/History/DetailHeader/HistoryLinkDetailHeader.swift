import SwiftUI

struct HistoryLinkDetailHeader: View {
    let websiteName: String
    let copiedAtText: String?
    let actions: [HistoryItemActionDescriptor]
    let copyContextID: [UUID]
    let onCopy: () async -> Bool
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistoryDetailHeaderMetadata(
                    sourceAppName: websiteName,
                    copiedAtText: copiedAtText
                )
            },
            actions: {
                HistoryDetailHeaderActionButtons(
                    actions: actions,
                    copyContextID: copyContextID,
                    onCopy: onCopy,
                    onSelect: onSelectAction
                )
            }
        )
    }
}
