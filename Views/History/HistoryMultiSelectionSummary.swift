import SwiftUI

struct HistoryMultiSelectionSummary: View {
    let items: [ClipboardItem]
    let store: ClipboardStore
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let onPasteItem: (ClipboardItem) -> Void
    let onCopyItem: (ClipboardItem) -> Void
    let onTogglePinItem: (ClipboardItem) -> Void
    let onDeleteItem: (ClipboardItem) -> Void
    let onJumpToHistoryItem: ((ClipboardItem) -> Void)?
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void

    @State private var expandedTextItemIDs: Set<UUID> = []
    @State private var collapsedItemIDs: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items) { item in
                let isCollapsed = collapsedItemIDs.contains(item.id)

                VStack(spacing: 0) {
                    HistoryMultiSelectionCardHeader(
                        item: item,
                        isCollapsed: isCollapsed,
                        onToggleCollapsed: {
                            toggleCollapsed(item.id)
                        },
                        onPaste: {
                            onPasteItem(item)
                        },
                        onCopy: {
                            onCopyItem(item)
                        },
                        onTogglePin: {
                            onTogglePinItem(item)
                        },
                        onDelete: {
                            onDeleteItem(item)
                        },
                        onJumpToHistory: onJumpToHistoryItem.map { action in
                            { action(item) }
                        }
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
                            store: store,
                            isTextExpanded: expandedTextItemIDs.contains(item.id),
                            textDetailFontStyle: textDetailFontStyle,
                            textDetailFontSize: textDetailFontSize,
                            enableWebsitePreviews: enableWebsitePreviews,
                            onToggleExpandedText: {
                                toggleExpandedText(item.id)
                            },
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
        }
    }

    private var cardBackground: some ShapeStyle {
        Color.primary.opacity(0.04)
    }

    private func toggleExpandedText(_ itemID: UUID) {
        if expandedTextItemIDs.contains(itemID) {
            expandedTextItemIDs.remove(itemID)
        } else {
            expandedTextItemIDs.insert(itemID)
        }
    }

    private func toggleCollapsed(_ itemID: UUID) {
        if collapsedItemIDs.contains(itemID) {
            collapsedItemIDs.remove(itemID)
        } else {
            expandedTextItemIDs.remove(itemID)
            collapsedItemIDs.insert(itemID)
        }
    }
}

private struct HistoryMultiSelectionCardHeader: View {
    let item: ClipboardItem
    let isCollapsed: Bool
    let onToggleCollapsed: () -> Void
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onJumpToHistory: (() -> Void)?

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

                Text(HistoryViewModel.copiedAtText(for: item.timestamp))
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
                ClipboardItemActionMenuContent(
                    item: item,
                    onPaste: onPaste,
                    onCopy: onCopy,
                    onTogglePin: onTogglePin,
                    onDelete: onDelete,
                    onJumpToHistory: onJumpToHistory
                )
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
            return item.sourceAppDisplayName ?? "Unknown App"
        case .color:
            return item.colorPayload?.originalText ?? "Color"
        case .link:
            return item.linkPayload?.websiteName ?? "Website"
        }
    }

    private var itemTypeLabel: String {
        switch item.kind {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .color:
            return "Color"
        case .link:
            return "Link"
        }
    }
}

private struct HistoryMultiSelectionCardContent: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isTextExpanded: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let enableWebsitePreviews: Bool
    let onToggleExpandedText: () -> Void
    let onCopyOCRText: (String) -> Void
    let onCopyColorVariant: (String) -> Void

    var body: some View {
        switch ClipboardItemTypeRegistry.definition(for: item).detailContentKind {
        case .text:
            HistoryMultiSelectionTextPreview(
                text: store.fullText(for: item) ?? item.textContent ?? "",
                isExpanded: isTextExpanded,
                textDetailFontStyle: textDetailFontStyle,
                textDetailFontSize: textDetailFontSize,
                onToggleExpanded: onToggleExpandedText
            )
            .padding(.top, 16)

        case .image:
            HistoryImageDetailContent(
                item: item,
                previewImage: store.image(for: item),
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
        }
    }
}

private struct HistoryMultiSelectionTextPreview: View {
    private static let collapsedLineLimit = 10
    private static let overflowCharacterThreshold = 800

    let text: String
    let isExpanded: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let onToggleExpanded: () -> Void

    private var fontSize: CGFloat {
        CGFloat(textDetailFontSize.rawValue)
    }

    private var usesMonospacedFont: Bool {
        textDetailFontStyle == .monospaced
    }

    private var font: Font {
        usesMonospacedFont
            ? .system(size: fontSize, design: .monospaced)
            : .system(size: fontSize)
    }

    private var showsExpansionToggle: Bool {
        let explicitLineCount = text.components(separatedBy: .newlines).count
        return explicitLineCount > Self.collapsedLineLimit || text.count > Self.overflowCharacterThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)

            if showsExpansionToggle {
                Button(isExpanded ? "Show less" : "Show more", action: onToggleExpanded)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.82))
            }
        }
    }
}
