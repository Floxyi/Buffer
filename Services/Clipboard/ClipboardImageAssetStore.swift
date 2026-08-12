import AppKit
import Foundation
import ImageIO

final class ClipboardImageAssetStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directory: URL
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let fullImageCache = NSCache<NSString, NSImage>()
    private let imageDimensionsCache = NSCache<NSString, NSString>()

    init(fileManager: FileManager = .default, directory: URL) {
        self.fileManager = fileManager
        self.directory = directory
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }
        let cacheKey = filename as NSString
        if let cachedImage = fullImageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let image = NSImage(contentsOf: directory.appendingPathComponent(filename)) else {
            return nil
        }

        fullImageCache.setObject(image, forKey: cacheKey)
        return image
    }

    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? {
        guard let filename = item.imageFilename else { return nil }

        let pixelSize = max(1, Int(maxPixelSize.rounded()))
        let cacheKey = "\(filename)-\(pixelSize)" as NSString
        if let cachedThumbnail = thumbnailCache.object(forKey: cacheKey) {
            return cachedThumbnail
        }

        let url = directory.appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnailCache.setObject(image, forKey: cacheKey)
        return image
    }

    func imageDimensions(for item: ClipboardItem) -> String? {
        guard let filename = item.imageFilename else { return nil }

        let cacheKey = filename as NSString
        if let cachedDimensions = imageDimensionsCache.object(forKey: cacheKey) {
            return cachedDimensions as String
        }

        let url = directory.appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        else {
            return nil
        }

        let dimensions = "\(width)x\(height)" as NSString
        imageDimensionsCache.setObject(dimensions, forKey: cacheKey)
        return dimensions as String
    }

    func saveImage(_ data: Data) -> String? {
        let filename = UUID().uuidString + ".png"
        let url = directory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            cacheDecodedAssets(data: data, filename: filename)
            return filename
        } catch {
            BufferLogger.persistence.error("Failed to save image: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func itemSize(for item: ClipboardItem) -> Int? {
        guard let filename = item.imageFilename else { return nil }
        return fileSize(at: directory.appendingPathComponent(filename))
    }

    func deleteImageFile(for item: ClipboardItem) {
        guard let filename = item.imageFilename else { return }
        deleteImage(named: filename)
    }

    func deleteImage(named filename: String) {
        let cacheKey = filename as NSString
        fullImageCache.removeObject(forKey: cacheKey)
        imageDimensionsCache.removeObject(forKey: cacheKey)
        removeItemIfPresent(at: directory.appendingPathComponent(filename), label: "image")
    }

    private func cacheDecodedAssets(data: Data, filename: String) {
        let cacheKey = filename as NSString

        if let image = NSImage(data: data) {
            fullImageCache.setObject(image, forKey: cacheKey)
        }

        if let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0,
            height > 0
        {
            imageDimensionsCache.setObject("\(width)x\(height)" as NSString, forKey: cacheKey)
        }
    }

    private func fileSize(at url: URL) -> Int? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int
        } catch {
            BufferLogger.persistence.error(
                "Failed to read file size at \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return nil
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
