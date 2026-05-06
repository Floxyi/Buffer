import AppKit
import Foundation

@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published private(set) var isPaused = false

    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let activeApplicationProvider: ActiveApplicationProviding
    private var watchTask: Task<Void, Never>?
    private var lastChangeCount: Int
    private var lastContentHash = 0
    private var ignoreNextChange = false

    private let pollIntervalNanoseconds: UInt64 = 500_000_000

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        activeApplicationProvider: ActiveApplicationProviding
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.lastChangeCount = NSPasteboard.general.changeCount
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
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func ignoreNextCapturedChange() {
        ignoreNextChange = true
    }

    private func checkClipboard() {
        guard !isPaused else { return }

        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        let sourceApp = ClipboardCaptureSupport.currentSourceApplicationInfo(using: activeApplicationProvider)
        guard !settingsManager.shouldExcludeCapture(from: sourceApp) else { return }

        if let filePaths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String],
           filePaths.count == 1,
           let filePath = filePaths.first,
           ClipboardCaptureSupport.isImageFile(filePath) {
            let priorHash = lastContentHash
            Task { [store] in
                let processedImage = await Task.detached(priority: .userInitiated) {
                    ClipboardCaptureSupport.processedImageFile(filePath, skippingHash: priorHash)
                }.value

                guard let processedImage else {
                    return
                }

                guard let filename = store.saveImage(processedImage.pngData) else { return }
                let item = ClipboardItem.image(filename: filename, sourceApp: sourceApp)
                lastContentHash = processedImage.hash
                store.add(item)
            }
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let textSize = text.utf8.count
            let hashSource = textSize > ClipboardCaptureSupport.inlineTextLimit ? String(text.prefix(10_000)) : text
            let hash = hashSource.hashValue

            guard hash != lastContentHash else { return }
            lastContentHash = hash

            if textSize <= ClipboardCaptureSupport.inlineTextLimit {
                store.add(.text(text, sourceApp: sourceApp))
            } else {
                let preview = String(text.prefix(ClipboardCaptureSupport.previewLength))
                if let filename = store.saveText(text) {
                    store.add(.largeText(preview: preview, filename: filename, sourceApp: sourceApp))
                }
            }
            return
        }

        if let imageData = ClipboardCaptureSupport.imageData(from: pasteboard) {
            let hash = imageData.hashValue
            guard hash != lastContentHash else { return }

            lastContentHash = hash
            if let filename = store.saveImage(imageData) {
                store.add(.image(filename: filename, sourceApp: sourceApp))
            }
        }
    }
}
