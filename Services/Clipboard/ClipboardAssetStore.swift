import AppKit
import Foundation

final class ClipboardAssetStore: @unchecked Sendable, ClipboardAssetAccessing {
    private let paths: ClipboardStoragePaths
    private let imageStore: ClipboardImageAssetStore
    private let textStore: ClipboardTextAssetStore
    private let cleanup: ClipboardAssetCleanup

    init(fileManager: FileManager = .default, paths: ClipboardStoragePaths) {
        self.paths = paths
        self.imageStore = ClipboardImageAssetStore(fileManager: fileManager, directory: paths.imagesDirectory)
        self.textStore = ClipboardTextAssetStore(fileManager: fileManager, directory: paths.textsDirectory)
        self.cleanup = ClipboardAssetCleanup(fileManager: fileManager)
    }

    func ensureDirectoriesExist() {
        cleanup.ensureDirectoriesExist(paths: paths)
    }

    func cleanupOrphanedAssets(referencedBy items: [ClipboardItem]) {
        cleanup.cleanupOrphanedAssets(referencedBy: items, paths: paths)
    }

    func image(for item: ClipboardItem) -> NSImage? {
        imageStore.image(for: item)
    }

    func imageData(for item: ClipboardItem) -> Data? {
        imageStore.imageData(for: item)
    }

    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? {
        imageStore.thumbnail(for: item, maxPixelSize: maxPixelSize)
    }

    func imageDimensions(for item: ClipboardItem) -> String? {
        imageStore.imageDimensions(for: item)
    }

    func saveImage(_ data: Data) -> String? {
        imageStore.saveImage(data)
    }

    func saveText(_ text: String) -> String? {
        textStore.saveText(text)
    }

    func deleteImage(named filename: String) {
        imageStore.deleteImage(named: filename)
    }

    func deleteText(named filename: String) {
        textStore.deleteText(named: filename)
    }

    func fullText(for item: ClipboardItem) -> String? {
        textStore.fullText(for: item)
    }

    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk? {
        textStore.textChunk(for: item, charCount: charCount)
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        if let original = item.originalSizeBytes {
            return original
        }

        switch item.kind {
        case .text:
            return textStore.itemSize(for: item)
        case .image:
            return imageStore.itemSize(for: item)
        case .color:
            return item.colorPayload?.originalText.utf8.count
        case .link:
            return item.linkPayload?.originalText.utf8.count
        case .email:
            return item.emailPayload?.originalText.utf8.count
        }
    }

    func deleteAssociatedFiles(for item: ClipboardItem) {
        imageStore.deleteImageFile(for: item)
        textStore.deleteTextFile(for: item)
    }
}
