import AppKit
import Foundation

struct HistoryDetailViewState {
    var selectionCount = 0
    var selectedItem: ClipboardItem?
    var selectedItems: [ClipboardItem] = []
    var previewImage: NSImage?
    var chunkedText = ChunkedTextState()
    var isExtractingText = false
    var selectedItemSourceName: String?
    var selectedItemCopiedAtText: String?
    var selectedItemsTotalSizeText = AppFormatting.formattedByteCount(0)
    var textSelectionCount = 0
    var imageSelectionCount = 0
    var colorSelectionCount = 0
    var linkSelectionCount = 0
    var emailSelectionCount = 0
    var firstTextPreview: String?
    var actions: [HistoryItemActionDescriptor] = []
    var canSaveSelectedImage = false
    var canExtractSelectedImageText = false
    var selectedItemIsPinned = false
    var canJumpToHistorySelection = false
}
