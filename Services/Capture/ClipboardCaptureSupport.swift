import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardCaptureSupport {
    static let inlineTextLimit = 50_000
    static let previewLength = 500

    @MainActor
    static func currentSourceApplicationInfo(using provider: ActiveApplicationProviding) -> SourceApplicationInfo {
        provider.currentApplicationInfo
    }

    static func imageData(from pasteboard: NSPasteboard) -> Data? {
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff]

        for type in imageTypes {
            if let data = pasteboard.data(forType: type) {
                if let image = NSImage(data: data),
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    return pngData
                }
                return data
            }
        }

        return nil
    }

    @MainActor
    static func classifyTextItem(
        _ text: String,
        sourceApp: SourceApplicationInfo?,
        enableWebsitePreviews: Bool,
        websiteReachability: @escaping (URL) async -> Bool = ClipboardLinkValue.hasActiveWebServer,
        saveText: (String) -> String?
    ) async -> ClipboardItem {
        if let colorValue = ClipboardColorValue.parse(text) {
            return .color(colorValue, originalText: text, sourceApp: sourceApp)
        }

        if let url = ClipboardLinkValue.parseExplicit(
            text,
            requiringHTTPS: !enableWebsitePreviews
        ) {
            return .link(url, originalText: text, sourceApp: sourceApp)
        }

        if enableWebsitePreviews,
           let candidateURL = ClipboardLinkValue.parseImplicitWebsiteCandidate(text),
           await websiteReachability(candidateURL) {
            return .link(candidateURL, originalText: text, sourceApp: sourceApp)
        }

        return plainTextItem(text, sourceApp: sourceApp, saveText: saveText)
    }

    @MainActor
    private static func plainTextItem(
        _ text: String,
        sourceApp: SourceApplicationInfo?,
        saveText: (String) -> String?
    ) -> ClipboardItem {
        let textSize = text.utf8.count

        if textSize <= inlineTextLimit {
            return .text(text, sourceApp: sourceApp)
        }

        let preview = String(text.prefix(previewLength))
        if let filename = saveText(text) {
            return .largeText(preview: preview, filename: filename, sourceApp: sourceApp)
        }

        return .truncatedText(preview, originalSizeBytes: textSize, sourceApp: sourceApp)
    }

    static func isImageFile(_ filePath: String) -> Bool {
        let fileExtension = (filePath as NSString).pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }

        if let utType = UTType(filenameExtension: fileExtension) {
            return utType.conforms(to: .image)
        }
        return false
    }

    @MainActor
    static func processImageFile(
        _ filePath: String,
        sourceApp: SourceApplicationInfo,
        store: ClipboardStore,
        lastContentHash: Int,
        onCaptured: @escaping (_ hash: Int, _ item: ClipboardItem) -> Void
    ) {
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            let fileData = try Data(contentsOf: fileURL)

            guard let image = NSImage(data: fileData),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                BufferLogger.clipboard.error("Failed to convert image file: \(filePath, privacy: .public)")
                return
            }

            let hash = pngData.hashValue
            guard hash != lastContentHash else {
                return
            }

            if let filename = store.saveImage(pngData) {
                let item = ClipboardItem.image(filename: filename, sourceApp: sourceApp)
                DispatchQueue.main.async {
                    onCaptured(hash, item)
                }
            }
        } catch {
            BufferLogger.clipboard.error("Error processing image file \(filePath, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    static func processedImageFile(
        _ filePath: String,
        skippingHash lastContentHash: Int
    ) -> (pngData: Data, hash: Int)? {
        do {
            let fileURL = URL(fileURLWithPath: filePath)
            let fileData = try Data(contentsOf: fileURL)

            guard let image = NSImage(data: fileData),
                  let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmap.representation(using: .png, properties: [:]) else {
                BufferLogger.clipboard.error("Failed to convert image file: \(filePath, privacy: .public)")
                return nil
            }

            let hash = pngData.hashValue
            guard hash != lastContentHash else {
                return nil
            }

            return (pngData, hash)
        } catch {
            BufferLogger.clipboard.error("Error processing image file \(filePath, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
