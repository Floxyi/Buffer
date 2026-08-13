import AppKit
import Combine
import Foundation

struct HistoryDetailContext: Equatable {
    var selectedItem: ClipboardItem?
    var selectedItemsInVisualOrder: [ClipboardItem]
    var selectedItemsInActionOrder: [ClipboardItem]
    var isQueryActive: Bool

    static let empty = HistoryDetailContext(
        selectedItem: nil,
        selectedItemsInVisualOrder: [],
        selectedItemsInActionOrder: [],
        isQueryActive: false
    )
}

@MainActor
final class HistoryDetailModel: ObservableObject {
    private let store: ClipboardStore
    private let assetProvider: any ClipboardItemAssetProviding
    private let previewLoader: HistoryPreviewLoader
    private let previewStateController = HistoryPreviewStateController()
    private let detailViewStateProjector = HistoryDetailViewStateProjector()
    private let actionResolver = HistoryActionResolver()
    private let copiedAtFormatter = HistoryCopiedAtFormatter()

    private var previewState = HistoryPreviewState()
    private var totalSizeBytes: Int?
    private var detailTask: Task<Void, Never>?
    private var detailGeneration: UInt = 0
    private var selectedItemID: UUID?
    private var activeOCRItemID: UUID?
    private var activeOCRGeneration: UInt = 0
    private var activeOCRTask: Task<String?, Never>?
    private var context = HistoryDetailContext.empty

    @Published private(set) var viewState = HistoryDetailViewState()

    init(
        store: ClipboardStore,
        assetProvider: any ClipboardItemAssetProviding,
        ocrService: OCRServicing
    ) {
        self.store = store
        self.assetProvider = assetProvider
        self.previewLoader = HistoryPreviewLoader(
            assetProvider: assetProvider,
            ocrService: ocrService
        )
    }

    deinit {
        detailTask?.cancel()
        activeOCRTask?.cancel()
    }

    func update(_ context: HistoryDetailContext) {
        self.context = context
        detailGeneration &+= 1
        let generation = detailGeneration
        selectedItemID = context.selectedItem?.id
        detailTask?.cancel()
        detailTask = nil

        if activeOCRItemID != nil, activeOCRItemID != context.selectedItem?.id {
            cancelOCR()
        }

        guard let selectedItem = context.selectedItem else {
            totalSizeBytes = nil
            previewState = previewStateController.reset()
            publish()
            return
        }

        totalSizeBytes = immediateTotalSizeBytes(for: context.selectedItemsInVisualOrder)
        let cachedPreviewImage =
            ClipboardItemTypeRegistry.supportsImageAssets(for: selectedItem)
            ? previewLoader.assetProvider.cachedPreviewImage(for: selectedItem)
            : nil
        previewState = previewStateController.immediatePreview(
            for: selectedItem,
            cachedPreviewImage: cachedPreviewImage
        )
        publish()

        let previewLoader = previewLoader
        let selectedItems = context.selectedItemsInVisualOrder
        detailTask = Task { [weak self, assetProvider] in
            guard let self,
                !Task.isCancelled,
                self.detailGeneration == generation,
                self.selectedItemID == selectedItem.id
            else {
                return
            }

            var loadedPreviewState = self.previewState
            var loadedTotalSize = 0
            for item in selectedItems {
                guard !Task.isCancelled else { return }
                loadedTotalSize += await assetProvider.loadItemSize(for: item) ?? 0
            }

            if selectedItem.isFileBacked {
                loadedPreviewState.chunkedText = await previewLoader.loadInitialChunk(for: selectedItem)
            } else if selectedItem.kind == .image, loadedPreviewState.previewImage == nil {
                loadedPreviewState.previewImage = await previewLoader.loadPreviewImage(for: selectedItem)
            }

            guard !Task.isCancelled,
                self.detailGeneration == generation,
                self.selectedItemID == selectedItem.id
            else { return }
            self.previewState = loadedPreviewState
            self.totalSizeBytes = loadedTotalSize
            self.publish()
            self.detailTask = nil
        }
    }

    func waitUntilLoaded() async {
        while let task = detailTask {
            let generation = detailGeneration
            await task.value
            guard detailGeneration != generation else { return }
        }
    }

    func loadNextChunk() async {
        guard let item = context.selectedItem else { return }
        let generation = detailGeneration
        let nextState = await previewStateController.loadNextChunk(
            for: item,
            currentState: previewState,
            previewLoader: previewLoader
        )
        guard generation == detailGeneration, selectedItemID == item.id else { return }
        previewState = nextState
        publish()
    }

    func extractImageText(for item: ClipboardItem) async throws {
        guard context.selectedItem?.id == item.id else { return }
        guard activeOCRItemID != item.id else { return }

        cancelOCR()
        activeOCRItemID = item.id
        activeOCRGeneration &+= 1
        let generation = activeOCRGeneration
        previewState = previewStateController.beginExtracting(state: previewState)
        publish()

        let task = Task { [previewLoader, viewState] in
            await previewLoader.extractImageText(
                for: item,
                previewImage: viewState.selectedItem?.id == item.id ? viewState.previewImage : nil
            )
        }
        activeOCRTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        guard activeOCRGeneration == generation,
            activeOCRItemID == item.id,
            selectedItemID == item.id
        else { return }
        var persistenceError: Error?
        if !task.isCancelled, let result {
            do {
                try await store.setOCRText(
                    result.isEmpty ? String(localized: "No text found in this image.") : result,
                    for: item
                )
            } catch {
                persistenceError = error
            }
        }

        previewState = previewStateController.finishExtracting(state: previewState)
        activeOCRItemID = nil
        activeOCRTask = nil
        publish()

        if let persistenceError {
            throw persistenceError
        }
    }

    private func cancelOCR() {
        guard activeOCRItemID != nil || activeOCRTask != nil else { return }
        activeOCRGeneration &+= 1
        activeOCRTask?.cancel()
        activeOCRTask = nil
        activeOCRItemID = nil
        previewState = previewStateController.finishExtracting(state: previewState)
    }

    private func immediateTotalSizeBytes(for items: [ClipboardItem]) -> Int? {
        var totalSize = 0
        for item in items {
            let itemSize: Int?
            if let originalSizeBytes = item.originalSizeBytes {
                itemSize = originalSizeBytes
            } else {
                switch item.content {
                case .text(let payload) where payload.fileName == nil:
                    itemSize = payload.inlineText?.utf8.count
                case .color(let payload):
                    itemSize = payload.originalText.utf8.count
                case .link(let payload):
                    itemSize = payload.originalText.utf8.count
                case .email(let payload):
                    itemSize = payload.originalText.utf8.count
                case .text, .image:
                    itemSize = nil
                }
            }
            guard let itemSize else { return nil }
            totalSize += itemSize
        }
        return totalSize
    }

    private func publish() {
        viewState = detailViewStateProjector.project(
            selectedItem: context.selectedItem,
            selectedItemsInVisualOrder: context.selectedItemsInVisualOrder,
            selectedItemsInActionOrder: context.selectedItemsInActionOrder,
            isQueryActive: context.isQueryActive,
            previewState: previewState,
            selectedItemsTotalSizeBytes: totalSizeBytes,
            actionResolver: actionResolver,
            copiedAtFormatter: copiedAtFormatter
        )
    }
}
