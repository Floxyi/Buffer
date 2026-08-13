import AppKit
import Foundation

protocol ClipboardCaptureAssetPersisting: Sendable {
    func saveImageAsync(_ data: Data) async -> String?
    func saveTextAsync(_ text: String) async -> String?
    func discardCapturedImage(named filename: String) async
    func discardCapturedText(named filename: String) async
}

extension ClipboardStore: ClipboardCaptureAssetPersisting {}

actor ClipboardCaptureWorker {
    enum Result {
        case item(ClipboardItem, contentHash: Int)
        case none
    }

    func processImageFile(
        at filePath: String,
        sourceApp: SourceApplicationInfo?,
        skippingHash lastContentHash: Int,
        store: any ClipboardCaptureAssetPersisting
    ) async -> Result {
        guard !Task.isCancelled else {
            return .none
        }

        guard
            let processedImage = BufferPerformanceDiagnostics.measure(
                .clipboardCapture,
                operation: {
                    ClipboardCaptureSupport.processedImageFile(
                        filePath,
                        skippingHash: lastContentHash
                    )
                })
        else {
            return .none
        }

        guard !Task.isCancelled else {
            return .none
        }

        guard let filename = await store.saveImageAsync(processedImage.pngData) else {
            return .none
        }

        guard !Task.isCancelled else {
            await store.discardCapturedImage(named: filename)
            return .none
        }

        return .item(.image(filename: filename, sourceApp: sourceApp), contentHash: processedImage.hash)
    }

    func processText(
        _ preparedText: PreparedClipboardText,
        sourceApp: SourceApplicationInfo?,
        enableWebsitePreviews: Bool,
        store: any ClipboardCaptureAssetPersisting
    ) async -> Result {
        guard !Task.isCancelled else {
            return .none
        }

        let token = BufferPerformanceDiagnostics.begin(.clipboardCapture)
        let item = await ClipboardCaptureSupport.classifyTextItem(
            preparedText.text,
            sourceApp: sourceApp,
            enableWebsitePreviews: enableWebsitePreviews,
            saveText: { text in
                guard !Task.isCancelled,
                    let filename = await store.saveTextAsync(text)
                else {
                    return nil
                }

                guard !Task.isCancelled else {
                    await store.discardCapturedText(named: filename)
                    return nil
                }

                return filename
            }
        )
        BufferPerformanceDiagnostics.end(token)

        guard !Task.isCancelled else {
            if let filename = item.textFilename {
                await store.discardCapturedText(named: filename)
            }
            return .none
        }

        return .item(item, contentHash: preparedText.contentHash)
    }

    func processPasteboardImage(
        _ imageData: Data,
        sourceApp: SourceApplicationInfo?,
        store: any ClipboardCaptureAssetPersisting
    ) async -> Result {
        guard !Task.isCancelled else {
            return .none
        }

        let hash = imageData.hashValue
        let normalizedData = BufferPerformanceDiagnostics.measure(.clipboardCapture) {
            ClipboardCaptureSupport.normalizedImageData(from: imageData) ?? imageData
        }

        guard !Task.isCancelled else {
            return .none
        }

        guard let filename = await store.saveImageAsync(normalizedData) else {
            return .none
        }

        guard !Task.isCancelled else {
            await store.discardCapturedImage(named: filename)
            return .none
        }

        return .item(.image(filename: filename, sourceApp: sourceApp), contentHash: hash)
    }
}
