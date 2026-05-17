import SwiftUI

struct HistoryLinkDetailHeader: View {
    let websiteName: String
    let selectedItemIsPinned: Bool
    let showsJumpToHistory: Bool
    let copiedAtText: String?
    let onCopy: () -> Void
    let onOpenLink: () -> Void
    let onJumpToHistory: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistoryDetailHeaderMetadata(
                    sourceAppName: websiteName,
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

                    BufferGlassSymbolButton(
                        help: "Open website",
                        systemName: "arrow.up.forward.app",
                        action: onOpenLink
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
