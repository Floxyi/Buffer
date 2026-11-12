import SwiftUI

enum HistoryItemAction: Hashable {
    case copy
    case openLink
    case composeEmail
    case jumpToHistory
    case saveImage
    case extractImageText
    case toggleBookmark
    case togglePin
    case delete

    var label: String {
        switch self {
        case .copy: return String(localized: "Copy")
        case .openLink: return String(localized: "Open Website")
        case .composeEmail: return String(localized: "Compose Email")
        case .jumpToHistory: return String(localized: "Jump to History")
        case .saveImage: return String(localized: "Save Image")
        case .extractImageText: return String(localized: "Extract Text")
        case .toggleBookmark: return String(localized: "Bookmark")
        case .togglePin: return String(localized: "Pin")
        case .delete: return String(localized: "Delete")
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
        case .toggleBookmark: return "bookmark"
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
    let isBookmarkedVariant: Bool

    var id: HistoryItemAction { action }

    init(
        action: HistoryItemAction,
        title: String? = nil,
        systemImage: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        isPinnedVariant: Bool = false,
        isBookmarkedVariant: Bool = false
    ) {
        self.action = action
        self.title = title ?? action.label
        self.systemImage = systemImage ?? action.systemImage
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
        self.isPinnedVariant = isPinnedVariant
        self.isBookmarkedVariant = isBookmarkedVariant
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
    let onCopy: () async -> Bool
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        switch ClipboardItemPresentation.definition(for: item).detailContentKind {
        case .text:
            HistoryTextDetailHeader(
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                actions: actions,
                copyContextID: [item.id],
                onCopy: onCopy,
                onSelectAction: onSelectAction
            )
        case .image:
            HistoryImageDetailHeader(
                sourceAppName: sourceAppName,
                copiedAtText: copiedAtText,
                actions: actions,
                copyContextID: [item.id],
                onCopy: onCopy,
                onSelectAction: onSelectAction
            )
        case .color:
            HistoryColorDetailHeader(
                originalText: item.colorPayload?.originalText ?? "",
                copiedAtText: copiedAtText,
                actions: actions,
                copyContextID: [item.id],
                onCopy: onCopy,
                onSelectAction: onSelectAction
            )
        case .link:
            HistoryLinkDetailHeader(
                websiteName: item.linkPayload?.websiteName ?? "Website",
                copiedAtText: copiedAtText,
                actions: actions,
                copyContextID: [item.id],
                onCopy: onCopy,
                onSelectAction: onSelectAction
            )
        case .email:
            HistoryTextDetailHeader(
                sourceAppName: "Email",
                copiedAtText: copiedAtText,
                actions: actions,
                copyContextID: [item.id],
                onCopy: onCopy,
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
    let copyContextID: [UUID]
    let onCopy: () async -> Bool
    let onSelect: (HistoryItemAction) -> Void

    var body: some View {
        HistoryDetailHeaderButtonRow {
            ForEach(actions) { descriptor in
                if descriptor.action == .copy {
                    HistoryCopyConfirmationButton(
                        descriptor: descriptor,
                        contextID: copyContextID,
                        onCopy: onCopy
                    )
                } else {
                    BufferGlassSymbolButton(
                        help: descriptor.title,
                        systemName: descriptor.systemImage,
                        tint: symbolTint(for: descriptor),
                        action: {
                            onSelect(descriptor.action)
                        }
                    )
                    .disabled(!descriptor.isEnabled)
                }
            }
        }
    }

    private func symbolTint(for descriptor: HistoryItemActionDescriptor) -> Color {
        if descriptor.isPinnedVariant || descriptor.isBookmarkedVariant {
            return .accentColor
        }
        return .primary.opacity(0.82)
    }
}

private struct HistoryCopyConfirmationButton: View {
    private static let confirmationDuration = Duration.milliseconds(1_100)
    private static let transitionDuration = 0.001
    private static let returnDuration = 0.16

    let descriptor: HistoryItemActionDescriptor
    let contextID: [UUID]
    let onCopy: () async -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmed = false
    @State private var copyTask: Task<Void, Never>?
    @State private var resetTask: Task<Void, Never>?

    private var title: String {
        isConfirmed ? String(localized: "Copied") : descriptor.title
    }

    var body: some View {
        BufferGlassSymbolButton(
            help: title,
            systemName: isConfirmed ? "checkmark" : descriptor.systemImage,
            tint: .primary.opacity(0.82),
            contentTransition: reduceMotion || !isConfirmed ? .opacity : .symbolEffect,
            action: copy
        )
        .disabled(!descriptor.isEnabled || copyTask != nil)
        .accessibilityLabel(title)
        .accessibilityIdentifier("historyDetail.copy")
        .onChange(of: contextID) {
            reset()
        }
        .onDisappear {
            cancelTasks()
        }
    }

    private func copy() {
        guard copyTask == nil else { return }
        copyTask = Task { @MainActor in
            let succeeded = await onCopy()
            guard !Task.isCancelled else {
                copyTask = nil
                return
            }
            copyTask = nil
            guard succeeded else { return }
            showConfirmation()
        }
    }

    private func showConfirmation() {
        resetTask?.cancel()
        withAnimation(transitionAnimation) {
            isConfirmed = true
        }
        resetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: Self.confirmationDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            withAnimation(returnAnimation) {
                isConfirmed = false
            }
            resetTask = nil
        }
    }

    private var transitionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.1)
            : .snappy(duration: Self.transitionDuration, extraBounce: 0)
    }

    private var returnAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.1 : Self.returnDuration)
    }

    private func reset() {
        cancelTasks()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isConfirmed = false
        }
    }

    private func cancelTasks() {
        copyTask?.cancel()
        copyTask = nil
        resetTask?.cancel()
        resetTask = nil
    }
}

struct HistoryMultiSelectionHeader: View {
    let selectionCount: Int
    let selectedItemIDs: [UUID]
    let actions: [HistoryItemActionDescriptor]
    let onCopy: () async -> Bool
    let onSelectAction: (HistoryItemAction) -> Void

    var body: some View {
        HistorySingleDetailHeaderLayout(
            metadata: {
                HistorySelectionCountDetailHeaderMetadata(selectionCount: selectionCount)
            },
            actions: {
                HistoryDetailHeaderActionButtons(
                    actions: actions,
                    copyContextID: selectedItemIDs,
                    onCopy: onCopy,
                    onSelect: onSelectAction
                )
            }
        )
    }
}
