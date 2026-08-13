import Foundation

enum ClipboardLinkValue {
    static func parseExplicit(_ string: String, requiringHTTPS: Bool = false) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }

        return normalizedWebURL(from: trimmed, requiringHTTPS: requiringHTTPS)
    }

    static func parseImplicitWebsiteCandidate(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        guard !trimmed.contains("://") else { return nil }
        return normalizedWebURL(from: "https://\(trimmed)")
    }

    static func websiteName(for url: URL) -> String {
        let host = (url.host ?? url.absoluteString)
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)

        let labels =
            host
            .split(separator: ".")
            .map(String.init)

        let baseLabel: String
        if labels.count >= 3,
            labels[labels.count - 1].count == 2,
            labels[labels.count - 2].count <= 3
        {
            baseLabel = labels[labels.count - 3]
        } else if labels.count >= 2 {
            baseLabel = labels[labels.count - 2]
        } else {
            baseLabel = labels.first ?? host
        }

        return
            baseLabel
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { segment in
                let word = String(segment)
                guard !word.isEmpty else { return word }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    static func hasActiveWebServer(at url: URL) async -> Bool {
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 3
        headRequest.cachePolicy = .returnCacheDataElseLoad

        if await respondsToWebRequest(headRequest) {
            return true
        }

        var getRequest = URLRequest(url: url)
        getRequest.httpMethod = "GET"
        getRequest.timeoutInterval = 3
        getRequest.cachePolicy = .returnCacheDataElseLoad
        getRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        return await respondsToWebRequest(getRequest)
    }

    private static func normalizedWebURL(from string: String, requiringHTTPS: Bool = false) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        guard let scheme = components.scheme?.lowercased(),
            requiringHTTPS ? scheme == "https" : (scheme == "http" || scheme == "https"),
            let host = components.host,
            hostLooksWebLike(host)
        else {
            return nil
        }

        components.scheme = scheme
        return components.url
    }

    private static func respondsToWebRequest(_ request: URLRequest) async -> Bool {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    private static func hostLooksWebLike(_ host: String) -> Bool {
        host.contains(".")
            && host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil
            && !host.contains("..")
    }
}
