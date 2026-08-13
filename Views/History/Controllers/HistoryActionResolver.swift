import Foundation

struct HistoryActionResolver {
    func resolveActions(
        for items: [ClipboardItem],
        allowsJumpToHistory: Bool,
        isExtractingText: Bool
    ) -> [HistoryItemActionDescriptor] {
        guard !items.isEmpty else { return [] }

        let allPinned = items.allSatisfy(\.isPinned)
        let pinDescriptor = HistoryItemActionDescriptor(
            action: .togglePin,
            title: allPinned ? String(localized: "Unpin") : String(localized: "Pin"),
            systemImage: allPinned ? "pin.slash" : "pin",
            isPinnedVariant: allPinned
        )
        let allBookmarked = items.allSatisfy(\.isBookmarked)
        let bookmarkDescriptor = HistoryItemActionDescriptor(
            action: .toggleBookmark,
            title: allBookmarked
                ? String(localized: "Remove Bookmark")
                : String(localized: "Bookmark"),
            systemImage: allBookmarked ? "bookmark.slash" : "bookmark",
            isBookmarkedVariant: allBookmarked
        )
        let canDeleteAny = items.contains { !$0.isProtectedFromDeletion }

        if items.count > 1 {
            var actions: [HistoryItemActionDescriptor] = [
                .init(action: .copy),
                bookmarkDescriptor,
                pinDescriptor,
            ]
            if canDeleteAny {
                actions.append(.init(action: .delete, isDestructive: true))
            }
            return actions
        }

        let item = items[0]
        var actions: [HistoryItemActionDescriptor] = [.init(action: .copy)]

        if ClipboardItemTypeRegistry.canOpenLink(for: item) {
            actions.append(.init(action: .openLink))
        }

        if ClipboardItemTypeRegistry.canComposeEmail(for: item) {
            actions.append(.init(action: .composeEmail))
        }

        if allowsJumpToHistory {
            actions.append(.init(action: .jumpToHistory))
        }

        if ClipboardItemTypeRegistry.canSaveImage(for: item) {
            actions.append(.init(action: .saveImage))
        }

        if ClipboardItemTypeRegistry.canExtractImageText(for: item) {
            actions.append(
                .init(
                    action: .extractImageText,
                    systemImage: isExtractingText ? "ellipsis.circle" : HistoryItemAction.extractImageText.systemImage,
                    isEnabled: item.ocrText == nil && !isExtractingText
                )
            )
        }

        actions.append(bookmarkDescriptor)
        actions.append(pinDescriptor)
        if canDeleteAny {
            actions.append(.init(action: .delete, isDestructive: true))
        }
        return actions
    }
}
