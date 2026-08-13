import Foundation

struct HistorySelectionViewState {
    var selectedIDs: Set<UUID> = []
    var selectedActionOrderIDs: [UUID] = []
    var selectedIndex = 0
    var selectedID: UUID?
}
