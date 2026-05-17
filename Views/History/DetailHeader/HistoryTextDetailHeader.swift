import SwiftUI

struct HistoryTextDetailHeader: View {
    let selectedItemIsPinned: Bool
    let showsJumpToHistory: Bool
    let sourceAppName: String?
    let copiedAtText: String?
    let onCopy: () -> Void
    let onJumpToHistory: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistoryDetailHeaderMetadata(
                    sourceAppName: sourceAppName,
                    copiedAtText: copiedAtText
                )
            },
            actions: {
                HistoryDetailHeaderButtonRow {
                    BufferGlassSymbolButton(
                        help: "Copy",
                        systemName: "doc.on.doc",
                        action: onCopy
                    )

                    if showsJumpToHistory {
                        BufferGlassSymbolButton(
                            help: "Jump to history",
                            systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                            action: onJumpToHistory
                        )
                    }

                    HistoryCommonDetailHeaderActions(
                        selectedItemIsPinned: selectedItemIsPinned,
                        onTogglePin: onTogglePin,
                        onDelete: onDelete
                    )
                }
            }
        )
    }
}
