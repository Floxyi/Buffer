import AppKit
import SwiftUI

struct HistoryPanelSurfaceBackground: View {
    @Environment(\.bufferAppearance) private var appearance

    var body: some View {
        switch appearance.surfaceStyle {
        case .glass:
            Rectangle().fill(.regularMaterial).opacity(0.16)
        case .transparent:
            Color.clear
        case .opaque:
            Color(nsColor: .controlBackgroundColor)
        }
    }
}

struct HistoryDetailPane: View {
    let detailState: HistoryDetailViewState
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let showsSpacesAndTabs: Bool
    let enableWebsitePreviews: Bool
    let assetProvider: any ClipboardItemAssetProviding
    let actionsForItem: (ClipboardItem) -> [HistoryItemActionDescriptor]
    let onSelectItemAction: (ClipboardItem, HistoryItemAction) -> Void
    let onSelectAction: (HistoryItemAction) -> Void
    let onDownloadAllImages: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void
    let onLoadNextChunk: (ClipboardItem) -> Void

    private var viewportMode: HistoryDetailViewportMode {
        HistoryDetailViewportMode(
            selectionCount: detailState.selectionCount,
            selectedItem: detailState.selectedItem
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selectedItem = detailState.selectedItem, detailState.selectionCount == 1 {
                HistoryDetailHeader(
                    item: selectedItem,
                    sourceAppName: detailState.selectedItemSourceName,
                    copiedAtText: detailState.selectedItemCopiedAtText,
                    actions: detailState.actions,
                    onSelectAction: onSelectAction
                )
            } else {
                HistoryMultiSelectionHeader(
                    selectionCount: detailState.selectionCount,
                    actions: detailState.actions,
                    onSelectAction: onSelectAction
                )
            }

            BufferPanelSeparator(isVertical: false)

            Group {
                switch viewportMode {
                case .fitted:
                    HistoryDetailFittedView {
                        detailContent
                    }
                case .scrollable:
                    HistoryDetailScrollView(
                        resetID: HistoryDetailScrollResetID(detailState: detailState)
                    ) {
                        detailContent
                    }
                }
            }
            .padding(.trailing, 1)
        }
        .background {
            HistoryPanelSurfaceBackground()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if detailState.selectionCount > 1 {
            HistoryMultiSelectionSummary(
                items: detailState.selectedItems,
                assetProvider: assetProvider,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                enableWebsitePreviews: enableWebsitePreviews,
                actionsForItem: actionsForItem,
                onSelectAction: onSelectItemAction,
                onCopyOCRText: onCopyOCRText,
                onCopyColorVariant: onCopyColorVariant
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else if let selectedItem = detailState.selectedItem {
            HistoryItemDetailContent(
                item: selectedItem,
                previewImage: detailState.previewImage,
                chunkedText: detailState.chunkedText,
                isExtractingText: detailState.isExtractingText,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                showsSpacesAndTabs: showsSpacesAndTabs,
                enableWebsitePreviews: enableWebsitePreviews,
                onCopyOCRText: onCopyOCRText,
                onCopyColorVariant: onCopyColorVariant,
                onLoadNextChunk: onLoadNextChunk
            )
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
