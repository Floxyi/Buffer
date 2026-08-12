import AppKit

@MainActor
struct HistoryPreviewStateController {
    func reset() -> HistoryPreviewState {
        HistoryPreviewState()
    }

    func immediatePreview(
        for item: ClipboardItem,
        cachedPreviewImage: NSImage?
    ) -> HistoryPreviewState {
        var state = reset()

        if ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
            state.previewImage = cachedPreviewImage
        } else if ClipboardItemTypeRegistry.supportsTextChunks(for: item), item.isFileBacked {
            return state
        } else {
            state.chunkedText.visibleText =
                item.textContent
                ?? item.colorPayload?.originalText
                ?? item.linkPayload?.originalText
                ?? ""
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
    ) async -> HistoryPreviewState {
        guard !currentState.chunkedText.isLoadingMore && currentState.chunkedText.hasMore else {
            return currentState
        }

        var nextState = currentState
        nextState.chunkedText = await previewLoader.loadNextChunk(
            for: item,
            currentState: currentState.chunkedText
        )
        return nextState
    }
}
