import AppKit
import SwiftUI

struct ClipboardItemRowAssets {
    let thumbnail: NSImage?
    let sourceAppIcon: NSImage?
    let imageDimensionsText: String?

    static let empty = ClipboardItemRowAssets(
        thumbnail: nil,
        sourceAppIcon: nil,
        imageDimensionsText: nil
    )

    func shouldTreatAsLoaded(for item: ClipboardItem) -> Bool {
        switch item.type {
        case .text:
            return true

        case .image:
            return thumbnail != nil || imageDimensionsText != nil
        }
    }
}

@MainActor
enum ClipboardItemRowAssetLoader {
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
    }()

    private static let sourceIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    private static var imageDimensionsTextCache: [UUID: String] = [:]
    private static var missingSourceIconKeys = Set<String>()

    static func loadAssets(
        for item: ClipboardItem,
        store: ClipboardStore,
        leadingVisualSize: CGFloat
    ) async -> ClipboardItemRowAssets {
        let thumbnail: NSImage?
        let imageDimensionsText: String?

        if item.type == .image {
            thumbnail = await loadThumbnail(
                for: item,
                store: store,
                leadingVisualSize: leadingVisualSize
            )

            imageDimensionsText = await loadImageDimensionsText(
                for: item,
                store: store
            )
        } else {
            thumbnail = nil
            imageDimensionsText = nil
        }

        let sourceAppIcon = await loadSourceApplicationIcon(for: item)

        return ClipboardItemRowAssets(
            thumbnail: thumbnail,
            sourceAppIcon: sourceAppIcon,
            imageDimensionsText: imageDimensionsText
        )
    }

    static func loadThumbnail(
        for item: ClipboardItem,
        store: ClipboardStore,
        leadingVisualSize: CGFloat
    ) async -> NSImage? {
        let pixelSize = leadingVisualSize * 2
        let key = thumbnailCacheKey(for: item, pixelSize: pixelSize)

        if let cachedThumbnail = thumbnailCache.object(forKey: key as NSString) {
            return cachedThumbnail
        }

        guard let thumbnail = store.thumbnail(for: item, maxPixelSize: pixelSize) else {
            return nil
        }

        thumbnailCache.setObject(thumbnail, forKey: key as NSString)

        return thumbnail
    }

    static func loadImageDimensionsText(
        for item: ClipboardItem,
        store: ClipboardStore
    ) async -> String? {
        if let cachedText = imageDimensionsTextCache[item.id] {
            return cachedText
        }

        guard let dimensionsText = store.imageDimensions(for: item) else {
            return nil
        }

        imageDimensionsTextCache[item.id] = dimensionsText

        return dimensionsText
    }

    static func loadSourceApplicationIcon(for item: ClipboardItem) async -> NSImage? {
        guard let key = sourceIconCacheKey(for: item) else {
            return nil
        }

        if let cachedIcon = sourceIconCache.object(forKey: key as NSString) {
            return cachedIcon
        }

        if missingSourceIconKeys.contains(key) {
            return nil
        }

        let iconImage = await loadSourceApplicationIconWithoutCache(for: item)

        guard let iconImage else {
            missingSourceIconKeys.insert(key)
            return nil
        }

        sourceIconCache.setObject(iconImage, forKey: key as NSString)
        missingSourceIconKeys.remove(key)

        return iconImage
    }

    static func prewarmSourceIcons(
        for items: [ClipboardItem],
        limit: Int = 40
    ) async {
        var seenKeys = Set<String>()
        var loadedCount = 0

        for item in items {
            if Task.isCancelled {
                return
            }

            guard let key = sourceIconCacheKey(for: item) else {
                continue
            }

            guard seenKeys.insert(key).inserted else {
                continue
            }

            if sourceIconCache.object(forKey: key as NSString) != nil {
                continue
            }

            if missingSourceIconKeys.contains(key) {
                continue
            }

            _ = await loadSourceApplicationIcon(for: item)

            loadedCount += 1
            if loadedCount >= limit {
                return
            }
        }
    }

    static func clearCaches() {
        thumbnailCache.removeAllObjects()
        sourceIconCache.removeAllObjects()
        imageDimensionsTextCache.removeAll()
        missingSourceIconKeys.removeAll()
    }

    static func removeCachedAssets(for itemID: UUID) {
        imageDimensionsTextCache.removeValue(forKey: itemID)
    }

    private static func thumbnailCacheKey(for item: ClipboardItem, pixelSize: CGFloat) -> String {
        "\(item.id.uuidString)-\(Int(pixelSize.rounded()))"
    }

    private static func sourceIconCacheKey(for item: ClipboardItem) -> String? {
        if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
            return "path:\(bundlePath)"
        }

        if let bundleIdentifier = item.sourceAppBundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }

        return nil
    }

    private static func loadSourceApplicationIconWithoutCache(for item: ClipboardItem) async -> NSImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let resolvedIcon: NSImage?

                if let bundlePath = item.sourceAppBundlePath, !bundlePath.isEmpty {
                    resolvedIcon = NSWorkspace.shared.icon(forFile: bundlePath)
                } else if let bundleIdentifier = item.sourceAppBundleIdentifier,
                          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    resolvedIcon = NSWorkspace.shared.icon(forFile: appURL.path)
                } else {
                    resolvedIcon = nil
                }

                guard let resolvedIcon else {
                    continuation.resume(returning: nil)
                    return
                }

                let iconCopy = resolvedIcon.copy() as? NSImage ?? resolvedIcon
                iconCopy.size = NSSize(width: 14, height: 14)

                continuation.resume(returning: iconCopy)
            }
        }
    }
}

enum ClipboardColorParser {
    static func parseColor(_ string: String) -> Color? {
        let trimmed = string.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            let hexStr = String(trimmed.dropFirst())
            if let color = parseHex(hexStr) {
                return color
            }
        }

        if trimmed.hasPrefix("rgb") {
            if let color = parseRGB(trimmed) {
                return color
            }
        }

        if trimmed.hasPrefix("hsl") {
            if let color = parseHSL(trimmed) {
                return color
            }
        }

        return nil
    }

    private static func parseHex(_ hexStr: String) -> Color? {
        let hex = hexStr.filter { $0.isHexDigit }

        if hex.count == 3 {
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return parseHex6(expanded)
        } else if hex.count == 6 {
            return parseHex6(hex)
        } else if hex.count == 8 {
            return parseHex8(hex)
        }

        return nil
    }

    private static func parseHex6(_ hex: String) -> Color? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private static func parseHex8(_ hex: String) -> Color? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255.0
        let g = Double((value >> 16) & 0xFF) / 255.0
        let b = Double((value >> 8) & 0xFF) / 255.0
        let a = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    private static func parseRGB(_ string: String) -> Color? {
        let isRGBA = string.hasPrefix("rgba")
        let startOffset = isRGBA ? 5 : 4

        guard string.count > startOffset + 1 else { return nil }
        guard string.hasSuffix(")") else { return nil }

        let startIdx = string.index(string.startIndex, offsetBy: startOffset)
        let endIdx = string.index(string.endIndex, offsetBy: -1)
        let content = String(string[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)

        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else { return nil }
        guard let r = Double(components[0]).map({ $0 / 255.0 }),
              let g = Double(components[1]).map({ $0 / 255.0 }),
              let b = Double(components[2]).map({ $0 / 255.0 }) else { return nil }

        let a = isRGBA && components.count >= 4 ? Double(components[3]) ?? 1.0 : 1.0

        return Color(red: r, green: g, blue: b, opacity: a)
    }

    private static func parseHSL(_ string: String) -> Color? {
        let isHSLA = string.hasPrefix("hsla")
        let startOffset = isHSLA ? 5 : 4

        guard string.count > startOffset + 1 else { return nil }
        guard string.hasSuffix(")") else { return nil }

        let startIdx = string.index(string.startIndex, offsetBy: startOffset)
        let endIdx = string.index(string.endIndex, offsetBy: -1)
        let content = String(string[startIdx..<endIdx]).trimmingCharacters(in: .whitespaces)

        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else { return nil }

        guard let h = Double(components[0].filter { $0.isNumber || $0 == "-" || $0 == "." }),
              let s = Double(components[1].filter { $0.isNumber || $0 == "." }),
              let l = Double(components[2].filter { $0.isNumber || $0 == "." }) else { return nil }

        let a = isHSLA && components.count >= 4 ? Double(components[3]) ?? 1.0 : 1.0

        let (r, g, b) = hslToRGB(h: h, s: s / 100.0, l: l / 100.0)

        return Color(red: r, green: g, blue: b, opacity: a)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        let h = h.truncatingRemainder(dividingBy: 360)
        let s = max(0, min(1, s))
        let l = max(0, min(1, l))

        if s == 0 {
            return (l, l, l)
        }

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }

        let hNorm = h / 360
        let r = hueToRGB(p, q, hNorm + 1 / 3)
        let g = hueToRGB(p, q, hNorm)
        let b = hueToRGB(p, q, hNorm - 1 / 3)

        return (r, g, b)
    }
}
