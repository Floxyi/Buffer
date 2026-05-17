import SwiftUI

struct HistoryDetailHeader: View {
    let item: ClipboardItem
    let selectedItemIsPinned: Bool
    let canExtractSelectedImageText: Bool
    let isExtractingText: Bool
    let showsJumpToHistory: Bool
    let sourceAppName: String?
    let copiedAtText: String?
    let onCopy: () -> Void
    let onSaveImage: () -> Void
    let onExtractText: () -> Void
    let onOpenLink: () -> Void
    let onJumpToHistory: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        switch ClipboardItemTypeRegistry.definition(for: item).detailContentKind {
        case .text:
            HistoryTextDetailHeader(
                selectedItemIsPinned: selectedItemIsPinned,
                showsJumpToHistory: showsJumpToHistory,
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                onCopy: onCopy,
                onJumpToHistory: onJumpToHistory,
                onTogglePin: onTogglePin,
                onDelete: onDelete
            )
        case .image:
            HistoryImageDetailHeader(
                selectedItemIsPinned: selectedItemIsPinned,
                canExtractSelectedImageText: canExtractSelectedImageText,
                isExtractingText: isExtractingText,
                showsJumpToHistory: showsJumpToHistory,
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                onCopy: onCopy,
                onSaveImage: onSaveImage,
                onExtractText: onExtractText,
                onJumpToHistory: onJumpToHistory,
                onTogglePin: onTogglePin,
                onDelete: onDelete
            )
        case .color:
            HistoryColorDetailHeader(
                originalText: item.colorPayload?.originalText ?? "",
                selectedItemIsPinned: selectedItemIsPinned,
                showsJumpToHistory: showsJumpToHistory,
                copiedAtText: copiedAtText,
                onCopy: onCopy,
                onJumpToHistory: onJumpToHistory,
                onTogglePin: onTogglePin,
                onDelete: onDelete
            )
        case .link:
            HistoryLinkDetailHeader(
                websiteName: item.linkPayload?.websiteName ?? "Website",
                selectedItemIsPinned: selectedItemIsPinned,
                showsJumpToHistory: showsJumpToHistory,
                copiedAtText: copiedAtText,
                onCopy: onCopy,
                onOpenLink: onOpenLink,
                onJumpToHistory: onJumpToHistory,
                onTogglePin: onTogglePin,
                onDelete: onDelete
            )
        }
    }
}

struct HistorySingleDetailHeaderLayout<Metadata: View, Actions: View>: View {
    let metadata: Metadata
    let actions: Actions

    init(
        @ViewBuilder metadata: () -> Metadata,
        @ViewBuilder actions: () -> Actions
    ) {
        self.metadata = metadata()
        self.actions = actions()
    }

    var body: some View {
        HStack {
            metadata

            Spacer()

            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(0.18)
        }
    }
}

struct HistoryDetailHeaderMetadata: View {
    let sourceAppName: String?
    let copiedAtText: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(sourceAppName ?? "Unknown App")
                .font(.system(size: 13))
                .foregroundColor(.primary.opacity(0.8))

            if let copiedAtText {
                Text(copiedAtText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}

struct HistoryDetailHeaderButtonRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .foregroundColor(.secondary)
        .font(.system(size: 13))
    }
}

struct HistoryCommonDetailHeaderActions: View {
    let selectedItemIsPinned: Bool
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            BufferGlassSymbolButton(
                help: selectedItemIsPinned ? "Unpin" : "Pin",
                systemName: selectedItemIsPinned ? "pin.fill" : "pin",
                tint: selectedItemIsPinned ? .accentColor : .secondary,
                action: onTogglePin
            )

            BufferGlassSymbolButton(
                help: "Delete",
                systemName: "trash",
                action: onDelete
            )
        }
    }
}

struct HistoryMultiSelectionHeader: View {
    let selectionCount: Int

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                Color.clear
                    .frame(width: 1, height: 1)
            },
            actions: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text("\(selectionCount) items selected")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
            }
        )
    }
}
