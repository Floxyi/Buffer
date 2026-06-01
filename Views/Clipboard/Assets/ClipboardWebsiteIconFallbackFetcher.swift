import AppKit
import Foundation

@MainActor
enum ClipboardWebsiteIconFallbackFetcher {
    static func faviconURL(for item: ClipboardItem) -> URL? {
        guard let url = item.linkPayload?.url else {
            return nil
        }

        return faviconURL(for: url)
    }

    static func faviconURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return nil
        }

        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func fetchIcon(for url: URL) async -> NSImage? {
        guard let iconURL = faviconURL(for: url) else {
            return nil
        }

        var request = URLRequest(url: iconURL)
        request.timeoutInterval = 5
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let iconImage = NSImage(data: data) else {
                return nil
            }

            return iconImage
        } catch {
            return nil
        }
    }

    static func loadImage(from itemProvider: NSItemProvider?) async -> NSImage? {
        guard let itemProvider else {
            return nil
        }

        guard itemProvider.canLoadObject(ofClass: NSImage.self) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            itemProvider.loadObject(ofClass: NSImage.self) { object, _ in
                continuation.resume(returning: object as? NSImage)
            }
        }
    }
}
