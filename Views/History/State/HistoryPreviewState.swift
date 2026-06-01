import AppKit

struct HistoryPreviewState {
    var previewImage: NSImage?
    var chunkedText = ChunkedTextState()
    var isExtractingText = false
}
