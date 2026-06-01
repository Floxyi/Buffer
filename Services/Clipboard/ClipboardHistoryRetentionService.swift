import Foundation

protocol ClipboardHistoryRetentionServicing {
    func cutoff(for retentionPeriod: HistoryRetentionPeriod, now: Date) -> Date?
    func prunedInitialItems(
        from items: [ClipboardItem],
        retentionPeriod: HistoryRetentionPeriod,
        persistence: any ClipboardHistoryPersisting,
        now: Date
    ) -> [ClipboardItem]
}

struct ClipboardHistoryRetentionService: ClipboardHistoryRetentionServicing {
    func cutoff(for retentionPeriod: HistoryRetentionPeriod, now: Date = Date()) -> Date? {
        guard let maxAge = retentionPeriod.maxAge else { return nil }
        return now.addingTimeInterval(-maxAge)
    }

    func prunedInitialItems(
        from items: [ClipboardItem],
        retentionPeriod: HistoryRetentionPeriod,
        persistence: any ClipboardHistoryPersisting,
        now: Date = Date()
    ) -> [ClipboardItem] {
        guard let cutoff = cutoff(for: retentionPeriod, now: now) else {
            return items
        }

        let retainedItems = items.filter { $0.timestamp >= cutoff }

        if retainedItems.count != items.count {
            persistence.saveHistory(retainedItems)
        }

        return retainedItems
    }
}
