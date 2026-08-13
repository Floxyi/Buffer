import AppKit
import Foundation

@MainActor
protocol ClipboardReadingPasteboard: AnyObject {
    var changeCount: Int { get }
    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any?
    func string(forType type: NSPasteboard.PasteboardType) -> String?
    func data(forType type: NSPasteboard.PasteboardType) -> Data?
}

extension NSPasteboard: ClipboardReadingPasteboard {}

@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published private(set) var isPaused = false

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let activeApplicationProvider: ActiveApplicationProviding
    private let pasteboard: ClipboardReadingPasteboard
    private let bufferApplicationInfo: SourceApplicationInfo
    private let captureWorker = ClipboardCaptureWorker()
    private var watchTask: Task<Void, Never>?
    private var pendingAsyncCaptureTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var lastContentHash = 0
    private var suppressedChangeCounts: Set<Int> = []

    private let pollIntervalNanoseconds: UInt64 = 500_000_000

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        activeApplicationProvider: ActiveApplicationProviding,
        pasteboard: ClipboardReadingPasteboard = NSPasteboard.general,
        bufferApplicationInfo: SourceApplicationInfo = .currentProcess
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.pasteboard = pasteboard
        self.bufferApplicationInfo = bufferApplicationInfo
        self.lastChangeCount = pasteboard.changeCount
    }

    func startWatching() {
        guard watchTask == nil else { return }

        watchTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                self.checkClipboard()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        pendingAsyncCaptureTask?.cancel()
        pendingAsyncCaptureTask = nil
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        lastChangeCount = pasteboard.changeCount
    }

    func suppressCapture(forChangeCount changeCount: Int) {
        guard changeCount > lastChangeCount else { return }
        suppressedChangeCounts.insert(changeCount)
    }

    func checkClipboard() {
        guard !isPaused else { return }

        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        pendingAsyncCaptureTask?.cancel()
        pendingAsyncCaptureTask = nil

        if suppressedChangeCounts.remove(currentChangeCount) != nil {
            discardStaleSuppressionReceipts(before: currentChangeCount)
            return
        }
        discardStaleSuppressionReceipts(before: currentChangeCount)

        let sourceApp = ClipboardCaptureSupport.currentSourceApplicationInfo(
            using: activeApplicationProvider,
            pasteboard: pasteboard,
            bufferApplicationInfo: bufferApplicationInfo
        )
        guard !settingsManager.shouldExcludeCapture(from: sourceApp) else { return }

        if let filePaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
            as? [String],
            filePaths.count == 1,
            let filePath = filePaths.first,
            ClipboardCaptureSupport.isImageFile(filePath)
        {
            let priorHash = lastContentHash
            pendingAsyncCaptureTask = Task { [weak self, store, sourceApp] in
                guard let self else { return }
                let result = await captureWorker.processImageFile(
                    at: filePath,
                    sourceApp: sourceApp,
                    skippingHash: priorHash,
                    store: store
                )

                guard !Task.isCancelled else { return }

                if case .item(let item, let contentHash) = result {
                    await self.commitCapturedItem(item, contentHash: contentHash)
                }
            }
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            guard
                let preparedText = PreparedClipboardText.make(
                    from: text,
                    whitespaceMode: settingsManager.clipboardWhitespaceMode
                )
            else {
                return
            }

            guard preparedText.contentHash != lastContentHash else { return }
            pendingAsyncCaptureTask = Task { [weak self, store, settingsManager, sourceApp] in
                guard let self else { return }
                let result = await captureWorker.processText(
                    preparedText,
                    sourceApp: sourceApp,
                    enableWebsitePreviews: settingsManager.enableWebsitePreviews,
                    store: store
                )

                guard !Task.isCancelled else { return }

                if case .item(let item, let contentHash) = result {
                    await self.commitCapturedItem(item, contentHash: contentHash)
                }
            }
            return
        }

        if let imageData = ClipboardCaptureSupport.imageData(from: pasteboard) {
            let hash = imageData.hashValue
            guard hash != lastContentHash else { return }

            pendingAsyncCaptureTask = Task { [weak self, store, sourceApp] in
                guard let self else { return }
                let result = await captureWorker.processPasteboardImage(
                    imageData,
                    sourceApp: sourceApp,
                    store: store
                )

                guard !Task.isCancelled else { return }

                if case .item(let item, let contentHash) = result {
                    await self.commitCapturedItem(item, contentHash: contentHash)
                }
            }
        }
    }

    private func commitCapturedItem(_ item: ClipboardItem, contentHash: Int) async {
        do {
            try await store.add(item)
            lastContentHash = contentHash
        } catch {
            await store.discardCapturedAssets(for: item)
        }
    }

    private func discardStaleSuppressionReceipts(before changeCount: Int) {
        suppressedChangeCounts = suppressedChangeCounts.filter { $0 > changeCount }
    }
}
