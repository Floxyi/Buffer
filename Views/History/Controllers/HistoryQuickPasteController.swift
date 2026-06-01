import AppKit
import Foundation

@MainActor
struct HistoryQuickPasteState {
    var showsQuickPasteNumbers = false
    var quickPasteNeedsModifierReset = false
}

@MainActor
struct HistoryQuickPasteController {
    func prepareForWindowOpen(
        using flags: NSEvent.ModifierFlags,
        forceModifierReset: Bool,
        state: HistoryQuickPasteState
    ) -> HistoryQuickPasteState {
        var nextState = state
        nextState.quickPasteNeedsModifierReset = forceModifierReset || !quickPasteRelevantFlags(from: flags).isEmpty
        nextState.showsQuickPasteNumbers = false
        return nextState
    }

    func handleModifierFlagsChange(
        _ flags: NSEvent.ModifierFlags,
        state: HistoryQuickPasteState,
        isQuickPasteEnabled: Bool
    ) -> HistoryQuickPasteState {
        var nextState = state
        let relevantFlags = quickPasteRelevantFlags(from: flags)

        if nextState.quickPasteNeedsModifierReset {
            if relevantFlags.isEmpty {
                nextState.quickPasteNeedsModifierReset = false
            }

            nextState.showsQuickPasteNumbers = false
            return nextState
        }

        nextState.showsQuickPasteNumbers = isQuickPasteEnabled && relevantFlags == .command
        return nextState
    }

    func resetForAppResignActive(state: HistoryQuickPasteState) -> HistoryQuickPasteState {
        var nextState = state
        nextState.showsQuickPasteNumbers = false
        nextState.quickPasteNeedsModifierReset = false
        return nextState
    }

    func badgeNumberByItemID(
        for filteredItems: [ClipboardItem],
        settings: SettingsManager
    ) -> [UUID: Int] {
        guard settings.quickPasteEnabled else { return [:] }

        var result: [UUID: Int] = [:]
        for (index, item) in addressableItems(in: filteredItems, settings: settings).enumerated() {
            result[item.id] = quickPasteBadgeNumber(for: index)
        }
        return result
    }

    func itemToPaste(
        at index: Int,
        in filteredItems: [ClipboardItem],
        settings: SettingsManager
    ) -> ClipboardItem? {
        guard settings.quickPasteEnabled else { return nil }
        return addressableItems(in: filteredItems, settings: settings)[safe: index]
    }

    private func quickPasteRelevantFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .shift, .option, .control])
    }

    private func addressableItems(
        in filteredItems: [ClipboardItem],
        settings: SettingsManager
    ) -> [ClipboardItem] {
        let itemsToAddress: [ClipboardItem]

        switch settings.quickPasteNumberingStart {
        case .pinnedSection:
            itemsToAddress = filteredItems
        case .normalEntries:
            let unpinnedItems = filteredItems.filter { !$0.isPinned }
            itemsToAddress = unpinnedItems.isEmpty ? filteredItems : unpinnedItems
        }

        return Array(itemsToAddress.prefix(settings.quickPasteEntryCount))
    }

    private func quickPasteBadgeNumber(for index: Int) -> Int {
        index == 9 ? 0 : index + 1
    }
}
