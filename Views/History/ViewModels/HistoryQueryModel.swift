import Foundation

struct HistoryQuerySnapshot: Sendable, Identifiable {
    let id: UUID
    let renderRevision: UInt64
    let query: ClipboardQuery
    let items: [ClipboardItem]
    let hitByItemID: [UUID: ClipboardSearchHit]
    let itemByID: [UUID: ClipboardItem]
    let itemIndexByID: [UUID: Int]
    let validItemIDs: Set<UUID>
    let displayCache: ClipboardListStructure.DisplayCache

    init(
        id: UUID = UUID(),
        renderRevision: UInt64 = 0,
        query: ClipboardQuery = ClipboardQuery(),
        items: [ClipboardItem] = [],
        hitByItemID: [UUID: ClipboardSearchHit] = [:],
        itemByID: [UUID: ClipboardItem] = [:],
        itemIndexByID: [UUID: Int] = [:],
        validItemIDs: Set<UUID> = [],
        displayCache: ClipboardListStructure.DisplayCache = .empty
    ) {
        self.id = id
        self.renderRevision = renderRevision
        self.query = query
        self.items = items
        self.hitByItemID = hitByItemID
        self.itemByID = itemByID
        self.itemIndexByID = itemIndexByID
        self.validItemIDs = validItemIDs
        self.displayCache = displayCache
    }
}

struct PreparedHistoryQuerySnapshot: Sendable {
    let queryGeneration: UInt64
    let historyRevision: UInt64
    let querySnapshot: HistoryQuerySnapshot
    let applicationFilterOptions: [HistoryApplicationFilterOption]
    let dateAvailability: HistoryDateAvailability
}

actor HistorySearchProjectionCoordinator {
    private struct DateAvailabilityCacheKey: Equatable {
        let historyRevision: UInt64
        let calendarIdentifier: String
        let timeZoneIdentifier: String
    }

    private var cachedApplicationOptionsRevision: UInt64?
    private var cachedApplicationOptions: [HistoryApplicationFilterOption] = []
    private var cachedDateAvailabilityKey: DateAvailabilityCacheKey?
    private var cachedDateAvailability = HistoryDateAvailability.empty

    func projectLatest(
        response: ClipboardSearchResponse?,
        items: [ClipboardItem],
        query: ClipboardQuery,
        queryGeneration: UInt64,
        historyRevision: UInt64,
        retaining selectedApplication: HistoryApplicationFilterOption?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) throws -> PreparedHistoryQuerySnapshot {
        try Task.checkCancellation()
        let snapshot: HistoryQuerySnapshot
        if let response {
            var allItemsByID: [UUID: ClipboardItem] = [:]
            allItemsByID.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                allItemsByID[item.id] = item
            }
            var orderedPairs: [(ClipboardItem, ClipboardSearchHit)] = []
            orderedPairs.reserveCapacity(response.hits.count)
            for (index, hit) in response.hits.enumerated() {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                if let item = allItemsByID[hit.itemID] { orderedPairs.append((item, hit)) }
            }
            snapshot = try makeSnapshot(
                pairs: orderedPairs,
                query: query,
                referenceDate: referenceDate,
                calendar: calendar
            )
        } else {
            var projectedItems: [ClipboardItem] = []
            projectedItems.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                if query.filters.matches(item) { projectedItems.append(item) }
            }
            snapshot = try makeLocalSnapshot(
                projectedItems: projectedItems,
                query: query,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
        try Task.checkCancellation()
        let options = try applicationOptions(
            for: items,
            historyRevision: historyRevision,
            retaining: selectedApplication
        )
        let dateAvailability = try dateAvailability(
            for: items,
            historyRevision: historyRevision,
            calendar: calendar
        )
        try Task.checkCancellation()
        return PreparedHistoryQuerySnapshot(
            queryGeneration: queryGeneration,
            historyRevision: historyRevision,
            querySnapshot: snapshot,
            applicationFilterOptions: options,
            dateAvailability: dateAvailability
        )
    }

    private func dateAvailability(
        for items: [ClipboardItem],
        historyRevision: UInt64,
        calendar: Calendar
    ) throws -> HistoryDateAvailability {
        let key = DateAvailabilityCacheKey(
            historyRevision: historyRevision,
            calendarIdentifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        guard key != cachedDateAvailabilityKey else {
            return cachedDateAvailability
        }
        let availability = try HistoryDateAvailability.make(
            from: items,
            calendar: calendar,
            checkCancellation: { index in
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
            }
        )
        cachedDateAvailabilityKey = key
        cachedDateAvailability = availability
        return availability
    }

    private func applicationOptions(
        for items: [ClipboardItem],
        historyRevision: UInt64,
        retaining selectedApplication: HistoryApplicationFilterOption?
    ) throws -> [HistoryApplicationFilterOption] {
        let baseOptions: [HistoryApplicationFilterOption]
        if cachedApplicationOptionsRevision == historyRevision {
            baseOptions = cachedApplicationOptions
        } else {
            baseOptions = try HistoryApplicationFilterOptions.make(
                from: items,
                checkCancellation: { index in
                    if index.isMultiple(of: 256) { try Task.checkCancellation() }
                }
            )
            cachedApplicationOptionsRevision = historyRevision
            cachedApplicationOptions = baseOptions
        }
        guard let selectedApplication,
            !baseOptions.contains(where: {
                $0.bundleIdentifier == selectedApplication.bundleIdentifier
            })
        else { return baseOptions }
        return (baseOptions + [selectedApplication]).sorted { lhs, rhs in
            let comparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    func applyingSnippets(
        _ snippetsByItemID: [UUID: ClipboardSearchSnippet],
        to snapshot: HistoryQuerySnapshot
    ) -> HistoryQuerySnapshot {
        var hits = snapshot.hitByItemID
        for (itemID, snippet) in snippetsByItemID {
            guard var hit = hits[itemID], hit.evidence.sessionID == snippet.sessionID,
                hit.evidence.field == snippet.field
            else { continue }
            hit.snippet = snippet
            hits[itemID] = hit
        }
        return HistoryQuerySnapshot(
            id: snapshot.id,
            renderRevision: snapshot.renderRevision &+ 1,
            query: snapshot.query,
            items: snapshot.items,
            hitByItemID: hits,
            itemByID: snapshot.itemByID,
            itemIndexByID: snapshot.itemIndexByID,
            validItemIDs: snapshot.validItemIDs,
            displayCache: snapshot.displayCache
        )
    }

    private func makeLocalSnapshot(
        projectedItems: [ClipboardItem],
        query: ClipboardQuery,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> HistoryQuerySnapshot {
        let snapshotID = UUID()
        var itemByID: [UUID: ClipboardItem] = [:]
        var itemIndexByID: [UUID: Int] = [:]
        itemByID.reserveCapacity(projectedItems.count)
        itemIndexByID.reserveCapacity(projectedItems.count)
        for (index, item) in projectedItems.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            itemByID[item.id] = item
            itemIndexByID[item.id] = index
        }
        return HistoryQuerySnapshot(
            id: snapshotID,
            query: query,
            items: projectedItems,
            itemByID: itemByID,
            itemIndexByID: itemIndexByID,
            validItemIDs: Set(itemByID.keys),
            displayCache: try ClipboardListStructure.makeDisplayCacheCancellable(
                from: projectedItems,
                sourceSnapshotID: snapshotID,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }

    private func makeSnapshot(
        pairs: [(ClipboardItem, ClipboardSearchHit)],
        query: ClipboardQuery,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> HistoryQuerySnapshot {
        let snapshotID = UUID()
        var projectedItems: [ClipboardItem] = []
        var hitsByID: [UUID: ClipboardSearchHit] = [:]
        var itemByID: [UUID: ClipboardItem] = [:]
        var itemIndexByID: [UUID: Int] = [:]
        projectedItems.reserveCapacity(pairs.count)
        hitsByID.reserveCapacity(pairs.count)
        itemByID.reserveCapacity(pairs.count)
        itemIndexByID.reserveCapacity(pairs.count)
        for (index, pair) in pairs.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let item = pair.0
            let hit = pair.1
            projectedItems.append(item)
            hitsByID[item.id] = hit
            itemByID[item.id] = item
            itemIndexByID[item.id] = index
        }
        return HistoryQuerySnapshot(
            id: snapshotID,
            query: query,
            items: projectedItems,
            hitByItemID: hitsByID,
            itemByID: itemByID,
            itemIndexByID: itemIndexByID,
            validItemIDs: Set(itemByID.keys),
            displayCache: try ClipboardListStructure.makeSearchDisplayCacheCancellable(
                from: projectedItems,
                similarItemIDs: Set(
                    pairs.lazy.filter { $0.1.region == .similar }.map { $0.0.id }
                ),
                sourceSnapshotID: snapshotID,
                referenceDate: referenceDate,
                calendar: calendar
            )
        )
    }
}
