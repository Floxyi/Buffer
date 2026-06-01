import AppKit

@MainActor
struct HistoryPreviewStateController {
    func reset() -> HistoryPreviewState {
        HistoryPreviewState()
    }

    func loadPreview(
        for item: ClipboardItem,
        store: ClipboardStore,
        previewLoader: HistoryPreviewLoader
    ) -> HistoryPreviewState {
        var state = reset()

        if ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            state.previewImage = previewLoader.loadPreviewImage(for: item)
        } else if ClipboardItemTypeRegistry.supportsTextChunks(for: item), item.isFileBacked {
            state.chunkedText = previewLoader.loadInitialChunk(for: item)
        } else {
            state.chunkedText.visibleText = ClipboardItemTypeRegistry.pastedText(for: item, store: store) ?? ""
            state.chunkedText.reachedEOF = true
        }

        return state
    }

    func beginExtracting(state: HistoryPreviewState) -> HistoryPreviewState {
        var nextState = state
        nextState.isExtractingText = true
        return nextState
    }

    func finishExtracting(state: HistoryPreviewState) -> HistoryPreviewState {
        var nextState = state
        nextState.isExtractingText = false
        return nextState
    }

    func loadNextChunk(
        for item: ClipboardItem,
        currentState: HistoryPreviewState,
        previewLoader: HistoryPreviewLoader
    ) -> HistoryPreviewState {
        guard !currentState.chunkedText.isLoadingMore && currentState.chunkedText.hasMore else {
            return currentState
        }

        var nextState = currentState
        nextState.chunkedText = previewLoader.loadNextChunk(
            for: item,
            currentState: currentState.chunkedText
        )
        return nextState
    }
}
