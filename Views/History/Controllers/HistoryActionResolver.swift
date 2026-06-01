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
            title: allPinned ? "Unpin" : "Pin",
            systemImage: allPinned ? "pin.slash" : "pin",
            isPinnedVariant: allPinned
        )

        if items.count > 1 {
            return [
                .init(action: .copy),
                pinDescriptor,
                .init(action: .delete, isDestructive: true)
            ]
        }

        let item = items[0]
        var actions: [HistoryItemActionDescriptor] = [.init(action: .copy)]

        if ClipboardItemTypeRegistry.canOpenLink(for: item) {
            actions.append(.init(action: .openLink))
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

        actions.append(pinDescriptor)
        actions.append(.init(action: .delete, isDestructive: true))
        return actions
    }
}
