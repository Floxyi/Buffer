import Foundation

final class ClipboardAssetCleanup: @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func ensureDirectoriesExist(paths: ClipboardStoragePaths) {
        createDirectoryIfNeeded(at: paths.storageDirectory, label: "storage")
        createDirectoryIfNeeded(at: paths.imagesDirectory, label: "images")
        createDirectoryIfNeeded(at: paths.textsDirectory, label: "texts")
    }

    func cleanupOrphanedAssets(referencedBy items: [ClipboardItem], paths: ClipboardStoragePaths) {
        let referencedImages = Set(items.compactMap(\.imageFilename))
        let referencedTexts = Set(items.compactMap(\.textFilename))

        cleanupOrphanedFiles(in: paths.imagesDirectory, keeping: referencedImages, label: "image")
        cleanupOrphanedFiles(in: paths.textsDirectory, keeping: referencedTexts, label: "text")
    }

    private func createDirectoryIfNeeded(at url: URL, label: String) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            BufferLogger.persistence.error(
                "Failed to create \(label, privacy: .public) directory: \(String(describing: error), privacy: .public)")
        }
    }

    private func cleanupOrphanedFiles(in directory: URL, keeping referencedNames: Set<String>, label: String) {
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }

        for fileURL in contents where !referencedNames.contains(fileURL.lastPathComponent) {
            removeItemIfPresent(at: fileURL, label: label)
        }
    }

    private func removeItemIfPresent(at url: URL, label: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            BufferLogger.persistence.error(
                "Failed to remove \(label, privacy: .public) file \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}
