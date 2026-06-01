import Foundation

struct ClipboardSearchIndex {
    private var cache: [UUID: String] = [:]

    mutating func value(for itemID: UUID, loader: () -> String) -> String {
        if let cached = cache[itemID] {
            return cached
        }

        let value = loader()
        cache[itemID] = value
        return value
    }

    mutating func prune(validIDs: Set<UUID>) {
        cache = cache.filter { validIDs.contains($0.key) }
    }
}
