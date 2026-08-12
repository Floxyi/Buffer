import Foundation

@MainActor
final class ClipboardListContextMenuState: ObservableObject {
    @Published private(set) var highlightedItemID: UUID?

    func highlight(_ itemID: UUID?) {
        highlightedItemID = itemID
    }

    func clear() {
        highlightedItemID = nil
    }
}
