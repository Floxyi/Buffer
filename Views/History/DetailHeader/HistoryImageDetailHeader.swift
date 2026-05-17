import SwiftUI

struct HistoryImageDetailHeader: View {
    let selectedItemIsPinned: Bool
    let canExtractSelectedImageText: Bool
    let isExtractingText: Bool
    let showsJumpToHistory: Bool
    let sourceAppName: String?
    let copiedAtText: String?
    let onCopy: () -> Void
    let onSaveImage: () -> Void
    let onExtractText: () -> Void
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

                    BufferGlassSymbolButton(
                        help: "Save image",
                        systemName: "arrow.down.to.line",
                        action: onSaveImage
                    )

                    BufferGlassSymbolButton(
                        help: "Extract Text from Image",
                        systemName: isExtractingText ? "ellipsis.circle" : "text.viewfinder",
                        action: onExtractText
                    )
                    .disabled(!canExtractSelectedImageText)

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
