import AppKit
import SwiftUI

struct HistoryMultiSelectionCard: View {
    let item: ClipboardItem
    let assetProvider: any ClipboardItemAssetProviding
    let isCollapsed: Bool
    let isTextExpanded: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let actions: [HistoryItemActionDescriptor]
    let onToggleCollapsed: () -> Void
    let onToggleExpandedText: () -> Void
    let onSelectAction: (HistoryItemAction) -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HistoryMultiSelectionCardHeader(
                item: item,
                isCollapsed: isCollapsed,
                onToggleCollapsed: onToggleCollapsed,
                actions: actions,
                onSelectAction: onSelectAction
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(cardBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                    .opacity(isCollapsed ? 0 : 1)
            }

            if !isCollapsed {
                HistoryMultiSelectionCardContent(
                    item: item,
                    assetProvider: assetProvider,
                    isTextExpanded: isTextExpanded,
                    textDetailFontStyle: textDetailFontStyle,
                    textDetailFontSize: textDetailFontSize,
                    enableWebsitePreviews: enableWebsitePreviews,
                    onToggleExpandedText: onToggleExpandedText,
                    onCopyOCRText: onCopyOCRText,
                    onCopyColorVariant: onCopyColorVariant
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(cardBackground)
            }
        }
        .background(cardBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var cardBackground: some ShapeStyle {
        Color.primary.opacity(0.04)
    }
}

private struct HistoryMultiSelectionCardHeader: View {
    let item: ClipboardItem
    let isCollapsed: Bool
    let onToggleCollapsed: () -> Void
    let actions: [HistoryItemActionDescriptor]
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggleCollapsed) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.82))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .animation(.easeInOut(duration: 0.22), value: isCollapsed)
                    .contentShape(Rectangle())
                    .padding(.leading, 0.5)
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(primaryMetadata)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)

                Text(HistoryCopiedAtFormatter().string(for: item.timestamp))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            Text(itemTypeLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
                .lineLimit(1)

            Menu {
                HistoryActionMenuContent(actions: actions, onSelect: onSelectAction)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.82))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, -3)
            .padding(.trailing, 0.5)
        }
    }

    private var primaryMetadata: String {
        switch item.kind {
        case .text, .image:
            return item.sourceAppDisplayName ?? String(localized: "Unknown App")
        case .color:
            return item.colorPayload?.originalText ?? String(localized: "Color")
        case .link:
            return item.linkPayload?.websiteName ?? String(localized: "Website")
        case .email:
            return item.emailPayload?.address ?? String(localized: "Email")
        }
    }

    private var itemTypeLabel: String {
        switch item.kind {
        case .text:
            return String(localized: "Text")
        case .image:
            return String(localized: "Image")
        case .color:
            return String(localized: "Color")
        case .link:
            return String(localized: "Link")
        case .email:
            return String(localized: "Email")
        }
    }
}

private struct HistoryMultiSelectionCardContent: View {
    let item: ClipboardItem
    let assetProvider: any ClipboardItemAssetProviding
    let isTextExpanded: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let onToggleExpandedText: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void

    @State private var loadedText: String?
    @State private var previewImage: NSImage?
    @State private var loadedItemID: UUID?

    var body: some View {
        Group {
            switch ClipboardItemPresentation.definition(for: item).detailContentKind {
            case .text:
                HistoryMultiSelectionTextPreview(
                    text: currentLoadedText ?? item.textContent ?? "",
                    isExpanded: isTextExpanded,
                    textDetailFontStyle: textDetailFontStyle,
                    textDetailFontSize: textDetailFontSize,
                    onToggleExpanded: onToggleExpandedText
                )
                .padding(.top, 16)

            case .image:
                HistoryImageDetailContent(
                    item: item,
                    previewImage: currentPreviewImage ?? assetProvider.cachedPreviewImage(for: item),
                    isExtractingText: false,
                    onCopyOCRText: onCopyOCRText
                )
                .padding(.top, 16)
                .frame(maxHeight: 420)

            case .color:
                HistoryColorDetailContent(
                    item: item,
                    textDetailFontStyle: textDetailFontStyle,
                    textDetailFontSize: textDetailFontSize,
                    onCopyColorVariant: onCopyColorVariant
                )
                .padding(.top, 16)

            case .link:
                HistoryLinkDetailContent(
                    item: item,
                    enableWebsitePreviews: enableWebsitePreviews
                )
                .padding(.top, 16)
                .frame(minHeight: 220, maxHeight: 320)

            case .email:
                HistoryEmailDetailContent(
                    item: item,
                    textDetailFontStyle: textDetailFontStyle,
                    textDetailFontSize: textDetailFontSize
                )
                .padding(.top, 16)
            }
        }
        .task(id: item.id) {
            await loadPreviewAssets()
        }
    }

    private func loadPreviewAssets() async {
        loadedText = nil
        previewImage = nil
        loadedItemID = nil

        switch ClipboardItemPresentation.definition(for: item).detailContentKind {
        case .text where item.isFileBacked:
            let text = await assetProvider.loadFullText(for: item)
            guard !Task.isCancelled else { return }
            loadedText = text
            loadedItemID = item.id

        case .image:
            let image = await assetProvider.loadPreviewImage(for: item)
            guard !Task.isCancelled else { return }
            previewImage = image
            loadedItemID = item.id

        case .text, .color, .link, .email:
            break
        }
    }

    private var currentLoadedText: String? {
        loadedItemID == item.id ? loadedText : nil
    }

    private var currentPreviewImage: NSImage? {
        loadedItemID == item.id ? previewImage : nil
    }
}
