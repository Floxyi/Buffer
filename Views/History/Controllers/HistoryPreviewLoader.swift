import AppKit
import Foundation

@MainActor
struct HistoryPreviewLoader {
    let store: ClipboardStore
    let ocrService: OCRServicing

    func loadPreviewImage(for item: ClipboardItem) async -> NSImage? {
        await ClipboardImageAssetLoader.loadPreviewImage(for: item, store: store)
    }

    func loadInitialChunk(for item: ClipboardItem) -> ChunkedTextState {
        var state = ChunkedTextState()
        state.isLoadingMore = true

        if let result = store.textChunk(for: item, charCount: ChunkedTextState.initialChars) {
            state.visibleText = result.text
            state.totalBytes = result.totalBytes
            state.loadedCharCount = result.text.count
            state.reachedEOF = result.reachedEOF
        }

        state.isLoadingMore = false
        return state
    }

    func loadNextChunk(for item: ClipboardItem, currentState: ChunkedTextState) -> ChunkedTextState {
        var nextState = currentState
        nextState.isLoadingMore = true

        let nextCharCount = nextState.loadedCharCount + ChunkedTextState.chunkSize
        if let result = store.textChunk(for: item, charCount: nextCharCount) {
            nextState.visibleText = result.text
            nextState.totalBytes = result.totalBytes
            nextState.loadedCharCount = result.text.count
            nextState.reachedEOF = result.reachedEOF
        }

        nextState.isLoadingMore = false
        return nextState
    }

    func extractImageText(
        for item: ClipboardItem,
        previewImage: NSImage?
    ) async -> String? {
        let image: NSImage?
        if let previewImage {
            image = previewImage
        } else {
            image = await loadPreviewImage(for: item)
        }
        guard let image else { return nil }
        return await ocrService.recognizeText(from: image)
    }
}
