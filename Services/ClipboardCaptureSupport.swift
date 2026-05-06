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
