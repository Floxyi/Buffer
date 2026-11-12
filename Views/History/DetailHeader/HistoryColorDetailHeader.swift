import SwiftUI

struct HistoryColorDetailHeader: View {
    let originalText: String
    let copiedAtText: String?
    let actions: [HistoryItemActionDescriptor]
    let copyContextID: [UUID]
    let onCopy: () async -> Bool
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistoryDetailHeaderMetadata(
                    sourceAppName: originalText,
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
