import AppKit
import Foundation

@MainActor
enum ClipboardWebsiteIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 240
        return cache
    }()

    private static var missingKeys = Set<String>()

    static func cachedIcon(for url: URL) -> NSImage? {
        guard let key = cacheKey(for: url) else {
            return nil
        }

        return cache.object(forKey: key as NSString)
    }

    static func hasMarkedMissingIcon(for url: URL) -> Bool {
        guard let key = cacheKey(for: url) else {
            return false
        }

        return missingKeys.contains(key)
    }

    static func markMissing(for url: URL) {
        guard let key = cacheKey(for: url) else {
            return
        }

        missingKeys.insert(key)
    }

    static func store(_ image: NSImage, for url: URL) {
        guard let key = cacheKey(for: url) else {
            return
        }

        cache.setObject(normalizedIcon(from: image), forKey: key as NSString)
        missingKeys.remove(key)
    }

    static func clear() {
        cache.removeAllObjects()
        missingKeys.removeAll()
    }

    private static func cacheKey(for url: URL) -> String? {
        url.host.map { "website:\($0.lowercased())" }
    }

    private static func normalizedIcon(from image: NSImage) -> NSImage {
        let iconCopy = image.copy() as? NSImage ?? image

        if let idealSize = preferredIconSize(for: iconCopy) {
            iconCopy.size = idealSize
        }

        return iconCopy
    }

    private static func preferredIconSize(for image: NSImage) -> NSSize? {
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }

        if let largestRepresentation = bitmapRepresentations.max(by: {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }) {
            return scaledIconSize(
                width: CGFloat(largestRepresentation.pixelsWide),
                height: CGFloat(largestRepresentation.pixelsHigh)
            )
        }

        guard image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        return scaledIconSize(width: image.size.width, height: image.size.height)
    }

    private static func scaledIconSize(width: CGFloat, height: CGFloat) -> NSSize {
        let maxDimension: CGFloat = 128
        let currentMaxDimension = max(width, height)
        guard currentMaxDimension > maxDimension else {
            return NSSize(width: width, height: height)
        }

        let scale = maxDimension / currentMaxDimension
        return NSSize(width: width * scale, height: height * scale)
    }
}
