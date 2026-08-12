import SwiftUI

enum HistoryItemAction: Hashable {
    case copy
    case openLink
    case composeEmail
    case jumpToHistory
    case saveImage
    case extractImageText
    case togglePin
    case delete

    var label: String {
        switch self {
        case .copy: return "Copy"
        case .openLink: return "Open Website"
        case .composeEmail: return "Compose Email"
        case .jumpToHistory: return "Jump to History"
        case .saveImage: return "Save Image"
        case .extractImageText: return "Extract Text"
        case .togglePin: return "Pin"
        case .delete: return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .openLink: return "arrow.up.forward.app"
        case .composeEmail: return "envelope"
        case .jumpToHistory: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .saveImage: return "arrow.down.to.line"
        case .extractImageText: return "text.viewfinder"
        case .togglePin: return "pin"
        case .delete: return "trash"
        }
    }
}

struct HistoryItemActionDescriptor: Identifiable, Hashable {
    let action: HistoryItemAction
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let isDestructive: Bool
    let isPinnedVariant: Bool

    var id: HistoryItemAction { action }

    init(
        action: HistoryItemAction,
        title: String? = nil,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        isPinnedVariant: Bool = false
    ) {
        self.action = action
        self.title = title ?? action.label
        self.systemImage = systemImage ?? action.systemImage
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.isPinnedVariant = isPinnedVariant
    }
}

struct HistoryActionMenuContent: View {
    let actions: [HistoryItemActionDescriptor]
    let onSelect: (HistoryItemAction) -> Void

    var body: some View {
        ForEach(Array(actions.enumerated()), id: \.element.id) { index, descriptor in
            if index > 0 && descriptor.isDestructive {
                Divider()
            }

            Button(descriptor.title, systemImage: descriptor.systemImage) {
                onSelect(descriptor.action)
            }
            .disabled(!descriptor.isEnabled)
        }
    }
}

struct HistoryDetailHeader: View {
    let item: ClipboardItem
    let sourceAppName: String?
    let copiedAtText: String?
    let actions: [HistoryItemActionDescriptor]
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        switch ClipboardItemPresentation.definition(for: item).detailContentKind {
        case .text:
            HistoryTextDetailHeader(
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                actions: actions,
                onSelectAction: onSelectAction
            )
        case .image:
            HistoryImageDetailHeader(
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                actions: actions,
                onSelectAction: onSelectAction
            )
        case .color:
            HistoryColorDetailHeader(
                originalText: item.colorPayload?.originalText ?? "",
                copiedAtText: copiedAtText,
                actions: actions,
                onSelectAction: onSelectAction
            )
        case .link:
            HistoryLinkDetailHeader(
                websiteName: item.linkPayload?.websiteName ?? "Website",
                copiedAtText: copiedAtText,
                actions: actions,
                onSelectAction: onSelectAction
            )
        case .email:
            HistoryTextDetailHeader(
                sourceAppName: "Email",
                copiedAtText: copiedAtText,
                actions: actions,
                onSelectAction: onSelectAction
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

struct HistorySelectionCountDetailHeaderMetadata: View {
    let selectionCount: Int

    var body: some View {
        Text("\(selectionCount) items selected")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary.opacity(0.8))
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

struct HistoryDetailHeaderActionButtons: View {
    let actions: [HistoryItemActionDescriptor]
    let onSelect: (HistoryItemAction) -> Void

    var body: some View {
        HistoryDetailHeaderButtonRow {
            ForEach(actions) { descriptor in
                BufferGlassSymbolButton(
                    help: descriptor.title,
                    systemName: descriptor.systemImage,
                    tint: descriptor.isPinnedVariant ? .accentColor : .secondary,
                    action: {
                        onSelect(descriptor.action)
                    }
                )
                .disabled(!descriptor.isEnabled)
            }
        }
    }
}

struct HistoryMultiSelectionHeader: View {
    let selectionCount: Int
    let actions: [HistoryItemActionDescriptor]
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistorySelectionCountDetailHeaderMetadata(selectionCount: selectionCount)
            },
            actions: {
                HistoryDetailHeaderActionButtons(actions: actions, onSelect: onSelectAction)
            }
        )
    }
}
