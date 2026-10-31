import CryptoKit
import Foundation
import SQLite3

enum ClipboardSQLiteFaultPoint: Hashable, Sendable {
    case open
    case begin
    case prepare(operation: SQLiteOperation)
    case step(operation: SQLiteOperation)
    case commitBeforeCall
    case commitAfterCall
    case rollback
    case reopen
    case publishPostCommit
}

protocol ClipboardSQLiteFaultInjecting: Sendable {
    func injectedCode(at point: ClipboardSQLiteFaultPoint) -> Int32?
}

protocol ClipboardSQLiteRetryClock: Sendable {
    func sleep(
        for interval: TimeInterval,
        checkCancellation: @Sendable () throws -> Void
    ) throws
}

struct SystemClipboardSQLiteRetryClock: ClipboardSQLiteRetryClock {
    func sleep(
        for interval: TimeInterval,
        checkCancellation: @Sendable () throws -> Void
    ) throws {
        var remaining = interval
        while remaining > 0 {
            try checkCancellation()
            let slice = min(remaining, 0.005)
            Thread.sleep(forTimeInterval: slice)
            remaining -= slice
        }
        try checkCancellation()
    }
}

struct ClipboardSearchDatabaseDiagnostics: Sendable, Equatable {
    let preparedStatementCount: Int
    let selectedStoredStateCount: Int
    let totalChanges: Int
}

struct ClipboardSQLiteNoFaults: ClipboardSQLiteFaultInjecting {
    func injectedCode(at point: ClipboardSQLiteFaultPoint) -> Int32? { nil }
}

enum ClipboardSearchAssetState: Int32, Sendable {
    case complete = 0
    case pending = 1
}

struct ClipboardSearchStoredState: Sendable {
    let contentRevision: Data
    let sourceRevision: Data
    let ocrRevision: Data
    let metadataRevision: Data
    let assetState: ClipboardSearchAssetState
    let assetFingerprint: Data?
}

private struct ClipboardSearchRevisionBuilder {
    private var encoder = ClipboardLengthPrefixedBinaryEncoder()

    mutating func append(tag: UInt8, value: String?) {
        encoder.append(tag: tag, string: value)
    }

    func digest() -> Data { Data(SHA256.hash(data: encoder.data)) }
}

private struct ClipboardSearchFieldRevisions {
    let content: Data
    let source: Data
    let ocr: Data
    let metadata: Data

    static func make(for item: ClipboardItem, assetFingerprint: Data? = nil) -> Self {
        var content = ClipboardSearchRevisionBuilder()
        content.append(tag: 1, value: item.kind.rawValue)
        switch item.content {
        case .text(let payload):
            content.append(tag: 2, value: payload.fileName)
            if let assetFingerprint {
                content.append(tag: 8, value: assetFingerprint.base64EncodedString())
            }
            if payload.fileName == nil { content.append(tag: 3, value: payload.inlineText) }
        case .image(let payload):
            content.append(tag: 4, value: payload.filename)
        case .color(let payload):
            content.append(tag: 5, value: payload.originalText)
        case .link(let payload):
            content.append(tag: 6, value: payload.originalText)
        case .email(let payload):
            content.append(tag: 7, value: payload.originalText)
        }

        var source = ClipboardSearchRevisionBuilder()
        source.append(tag: 1, value: item.sourceAppDisplayName ?? "")
        var ocr = ClipboardSearchRevisionBuilder()
        ocr.append(tag: 1, value: item.ocrText ?? "")
        var metadata = ClipboardSearchRevisionBuilder()
        metadata.append(tag: 1, value: item.kind.rawValue)
        metadata.append(tag: 2, value: item.normalizedSourceAppBundleIdentifier ?? "")
        metadata.append(tag: 3, value: String(item.timestamp.timeIntervalSince1970.bitPattern))
        metadata.append(tag: 4, value: item.isBookmarked ? "1" : "0")
        return Self(
            content: content.digest(),
            source: source.digest(),
            ocr: ocr.digest(),
            metadata: metadata.digest()
        )
    }
}

private struct ClipboardSearchPreparedDocument {
    let item: ClipboardItem
    let revisions: ClipboardSearchFieldRevisions
    let content: String?
    let assetState: ClipboardSearchAssetState
    let assetFingerprint: Data?

    static func make(
        item: ClipboardItem,
        knownState: ClipboardSearchStoredState?,
        assetAccess: any ClipboardSearchAssetAccessing,
        checkCancellation: @Sendable () throws -> Void
    ) throws -> Self {
        let baseRevisions = ClipboardSearchFieldRevisions.make(for: item)
        guard case .text(let payload) = item.content, payload.fileName != nil else {
            let needsContent =
                knownState?.contentRevision != baseRevisions.content
                || knownState?.assetState == .pending
            guard needsContent else {
                return Self(
                    item: item,
                    revisions: baseRevisions,
                    content: nil,
                    assetState: .complete,
                    assetFingerprint: nil
                )
            }
            let content: String
            switch item.content {
            case .text(let payload): content = payload.inlineText ?? ""
            case .image: content = ""
            case .color(let payload): content = payload.originalText
            case .link(let payload): content = payload.originalText
            case .email(let payload): content = payload.originalText
            }
            return Self(
                item: item,
                revisions: baseRevisions,
                content: content,
                assetState: .complete,
                assetFingerprint: nil
            )
        }

        let currentFingerprint: ClipboardSearchAssetFingerprint
        do {
            try checkCancellation()
            currentFingerprint = try assetAccess.fingerprint(for: item)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let revisions = ClipboardSearchFieldRevisions(
                content: knownState?.contentRevision ?? baseRevisions.content,
                source: baseRevisions.source,
                ocr: baseRevisions.ocr,
                metadata: baseRevisions.metadata
            )
            return Self(
                item: item,
                revisions: revisions,
                content: knownState == nil ? (payload.inlineText ?? "") : nil,
                assetState: .pending,
                assetFingerprint: knownState?.assetFingerprint
            )
        }
        let fingerprintData = currentFingerprint.encoded
        let revisions = ClipboardSearchFieldRevisions.make(
            for: item,
            assetFingerprint: fingerprintData
        )
        let needsContent =
            knownState?.contentRevision != revisions.content
            || knownState?.assetState == .pending
            || knownState?.assetFingerprint != fingerprintData
        guard needsContent else {
            return Self(
                item: item,
                revisions: revisions,
                content: nil,
                assetState: .complete,
                assetFingerprint: fingerprintData
            )
        }

        do {
            let snapshot = try assetAccess.snapshot(
                for: item,
                checkCancellation: checkCancellation
            )
            let snapshotFingerprint = snapshot.fingerprint.encoded
            return Self(
                item: item,
                revisions: ClipboardSearchFieldRevisions.make(
                    for: item,
                    assetFingerprint: snapshotFingerprint
                ),
                content: snapshot.text,
                assetState: .complete,
                assetFingerprint: snapshotFingerprint
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let retainedRevisions = ClipboardSearchFieldRevisions(
                content: knownState?.contentRevision ?? revisions.content,
                source: revisions.source,
                ocr: revisions.ocr,
                metadata: revisions.metadata
            )
            return Self(
                item: item,
                revisions: retainedRevisions,
                content: knownState == nil ? (payload.inlineText ?? "") : nil,
                assetState: .pending,
                assetFingerprint: knownState?.assetFingerprint
            )
        }
    }
}

final class ClipboardSearchDatabase: @unchecked Sendable {
    private enum TemporaryQueryTable: String {
        case excludedDocuments = "query_excluded_documents"
        case terms = "query_terms"
    }

    private struct VocabularySnapshot {
        var tree: ClipboardPersistentFuzzyVocabulary
        let buildID: String?
        let generation: UInt64
        var appliedDeltaSequence: UInt64
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let writerLock = NSLock()
    private let readerLock = NSLock()
    private let snippetReaderLock = NSLock()
    private let maintenanceReaderLock = NSLock()
    private let lifecycleLock = NSLock()
    private let vocabularyLock = NSLock()
    private let diagnosticsLock = NSLock()
    private let databaseURL: URL
    private let faultInjector: any ClipboardSQLiteFaultInjecting
    private let retryClock: any ClipboardSQLiteRetryClock
    private var writer: OpaquePointer?
    private var reader: OpaquePointer?
    private var snippetReader: OpaquePointer?
    private var maintenanceReader: OpaquePointer?
    private var vocabulary: VocabularySnapshot?
    private var successfulVocabularyMutations = 0
    private var isVocabularyCompactionScheduled = false
    private var isInvalidated = false
    private var requiresIdleIntegrityCheck = false
    private var preparedStatementCount = 0
    private var selectedStoredStateCount = 0
    private var isClosed = false

    init(
        databaseURL: URL,
        openMode: SearchDatabaseOpenMode? = nil,
        faultInjector: any ClipboardSQLiteFaultInjecting = ClipboardSQLiteNoFaults(),
        retryClock: any ClipboardSQLiteRetryClock = SystemClipboardSQLiteRetryClock()
    ) throws {
        self.databaseURL = databaseURL
        self.faultInjector = faultInjector
        self.retryClock = retryClock
        let fileExists = FileManager.default.fileExists(atPath: databaseURL.path)
        let resolvedOpenMode = openMode ?? (fileExists ? .openExisting : .createEmpty)
        if resolvedOpenMode == .openExisting, !fileExists {
            throw ClipboardSearchServiceError.openDatabase("Search index does not exist")
        }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        try Self.excludeFromBackup(databaseURL.deletingLastPathComponent())

        writer = try Self.open(
            at: databaseURL,
            createIfNeeded: resolvedOpenMode == .createEmpty,
            faultInjector: faultInjector
        )
        try configure(writer)
        let version = try userVersion(writer)
        switch resolvedOpenMode {
        case .openExisting:
            guard version == ClipboardSearchSchema.currentVersion else {
                throw SearchDatabaseValidationError.schemaMismatch(
                    found: version,
                    expected: ClipboardSearchSchema.currentVersion
                )
            }
        case .createEmpty:
            guard version == 0 else {
                throw SearchDatabaseValidationError.schemaMismatch(
                    found: version,
                    expected: 0
                )
            }
            try createSchema()
        }
        try validateSchema()
        try validateControlVersions()
        try prepareControlState()
        try validateControlCounters()
        reader = try Self.open(at: databaseURL, createIfNeeded: false, faultInjector: faultInjector)
        try configure(reader)
        snippetReader = try Self.open(
            at: databaseURL,
            createIfNeeded: false,
            faultInjector: faultInjector
        )
        try configure(snippetReader)
        maintenanceReader = try Self.open(
            at: databaseURL,
            createIfNeeded: false,
            faultInjector: faultInjector
        )
        try configure(maintenanceReader)
        try secureFiles()
    }

    deinit {
        close()
    }

    func close() {
        lifecycleLock.withLock {
            guard !isClosed else { return }
            isClosed = true

            if let writer, !isInvalidated {
                _ = sqlite3_exec(
                    writer,
                    "UPDATE search_control SET clean_shutdown = 1 WHERE id = 1",
                    nil,
                    nil,
                    nil
                )
            }
            if let reader {
                sqlite3_close(reader)
                self.reader = nil
            }
            if let snippetReader {
                sqlite3_close(snippetReader)
                self.snippetReader = nil
            }
            if let maintenanceReader {
                sqlite3_close(maintenanceReader)
                self.maintenanceReader = nil
            }
            if let writer {
                sqlite3_close(writer)
                self.writer = nil
            }
        }
    }

    func interruptSearch() {
        if let reader { sqlite3_interrupt(reader) }
    }

    func interruptSnippets() {
        if let snippetReader { sqlite3_interrupt(snippetReader) }
    }

    func interruptMaintenance() {
        if let maintenanceReader { sqlite3_interrupt(maintenanceReader) }
        if let writer { sqlite3_interrupt(writer) }
    }

    func resetDiagnostics() {
        diagnosticsLock.withLock {
            preparedStatementCount = 0
            selectedStoredStateCount = 0
        }
    }

    func diagnostics() -> ClipboardSearchDatabaseDiagnostics {
        let counters = diagnosticsLock.withLock {
            (preparedStatementCount, selectedStoredStateCount)
        }
        let changes = writerLock.withLock {
            writer.map { Int(sqlite3_total_changes($0)) } ?? 0
        }
        return ClipboardSearchDatabaseDiagnostics(
            preparedStatementCount: counters.0,
            selectedStoredStateCount: counters.1,
            totalChanges: changes
        )
    }

    func checkpointForActivation() throws {
        try writerLock.withLock {
            guard let writer else {
                throw ClipboardSearchServiceError.openDatabase("Missing writer")
            }
            try executeRequired(
                "PRAGMA wal_checkpoint(TRUNCATE)",
                connection: writer,
                operation: "checkpoint shadow index"
            )
            try secureFiles()
        }
    }

    func indexedStates() throws -> [UUID: ClipboardSearchStoredState] {
        try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            var result: [UUID: ClipboardSearchStoredState] = [:]
            try withStatement(
                """
                SELECT d.item_id, d.content_revision, d.source_revision, d.ocr_revision,
                       m.metadata_revision, d.asset_state, d.asset_fingerprint
                FROM documents d JOIN search_metadata m ON m.document_id = d.rowid
                """,
                connection: writer,
                operationName: "read revisions"
            ) { statement in
                while true {
                    let code = sqlite3_step(statement)
                    if code == SQLITE_DONE { break }
                    try requireRow(code, connection: writer, operation: "read revisions")
                    guard let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)) else { continue }
                    result[id] = ClipboardSearchStoredState(
                        contentRevision: columnData(statement, 1),
                        sourceRevision: columnData(statement, 2),
                        ocrRevision: columnData(statement, 3),
                        metadataRevision: columnData(statement, 4),
                        assetState: ClipboardSearchAssetState(rawValue: sqlite3_column_int(statement, 5)) ?? .pending,
                        assetFingerprint: sqlite3_column_type(statement, 6) == SQLITE_NULL
                            ? nil : columnData(statement, 6)
                    )
                }
            }
            return result
        }
    }

    func storedStates(for itemIDs: some Collection<UUID>) throws -> [UUID: ClipboardSearchStoredState] {
        let ids = Array(Set(itemIDs))
        guard !ids.isEmpty else { return [:] }
        return try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            var result: [UUID: ClipboardSearchStoredState] = [:]
            for start in stride(from: 0, to: ids.count, by: 300) {
                let batch = Array(ids[start..<min(start + 300, ids.count)])
                let placeholders = batch.indices.map { "?\($0 + 1)" }.joined(separator: ",")
                try withStatement(
                    """
                    SELECT d.item_id, d.content_revision, d.source_revision, d.ocr_revision,
                           m.metadata_revision, d.asset_state, d.asset_fingerprint
                    FROM documents d JOIN search_metadata m ON m.document_id = d.rowid
                    WHERE d.item_id IN (\(placeholders))
                    """,
                    connection: writer,
                    operationName: "read selected revisions"
                ) { statement in
                    for (index, id) in batch.enumerated() {
                        try bind(
                            .text(id.uuidString),
                            to: statement,
                            index: Int32(index + 1),
                            connection: writer,
                            operation: "bind selected revision ID"
                        )
                    }
                    while true {
                        let code = sqlite3_step(statement)
                        if code == SQLITE_DONE { break }
                        try requireRow(code, connection: writer, operation: "read selected revisions")
                        guard let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)) else { continue }
                        result[id] = ClipboardSearchStoredState(
                            contentRevision: columnData(statement, 1),
                            sourceRevision: columnData(statement, 2),
                            ocrRevision: columnData(statement, 3),
                            metadataRevision: columnData(statement, 4),
                            assetState: ClipboardSearchAssetState(
                                rawValue: sqlite3_column_int(statement, 5)
                            ) ?? .pending,
                            assetFingerprint: sqlite3_column_type(statement, 6) == SQLITE_NULL
                                ? nil : columnData(statement, 6)
                        )
                        diagnosticsLock.withLock { selectedStoredStateCount += 1 }
                    }
                }
            }
            return result
        }
    }

    func reconcile(
        items: [ClipboardItem],
        knownStates: [UUID: ClipboardSearchStoredState],
        assetAccess: any ClipboardSearchAssetAccessing,
        cancellationToken: ClipboardSearchCancellationToken = ClipboardSearchCancellationToken()
    ) throws -> Int {
        let prepared = try items.map {
            try ClipboardSearchPreparedDocument.make(
                item: $0,
                knownState: knownStates[$0.id],
                assetAccess: assetAccess,
                checkCancellation: { try cancellationToken.checkCancellation() }
            )
        }
        let changed = prepared.filter { document in
            guard let known = knownStates[document.item.id] else { return true }
            return known.contentRevision != document.revisions.content
                || known.sourceRevision != document.revisions.source
                || known.ocrRevision != document.revisions.ocr
                || known.metadataRevision != document.revisions.metadata
                || known.assetState == .pending
        }
        guard !changed.isEmpty else { return try pendingAssetCount() }
        try writeTransaction(
            checkCancellation: { try cancellationToken.checkCancellation() },
            {
                guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
                for document in changed {
                    try upsert(document, knownState: knownStates[document.item.id], connection: writer)
                }
            })
        return try pendingAssetCount()
    }

    func remove(itemIDs: Set<UUID>) throws {
        guard !itemIDs.isEmpty else { return }
        try writeTransaction {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            for itemID in itemIDs {
                try execute(
                    "DELETE FROM documents WHERE item_id = ?1",
                    values: [.text(itemID.uuidString)],
                    connection: writer,
                    operation: "remove document"
                )
            }
        }
    }

    func apply(
        _ changes: [ClipboardSearchChange],
        currentSnapshot: [ClipboardItem],
        historyRevision: UInt64,
        assetAccess: any ClipboardSearchAssetAccessing,
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> Int {
        let stateIDs = changes.flatMap { change -> [UUID] in
            switch change {
            case .insert(let item), .updateContent(let item): return [item.id]
            case .reset: return currentSnapshot.map(\.id)
            case .updateOCR, .updateSource, .remove, .updateMetadata: return []
            }
        }
        let currentStates = try storedStates(for: stateIDs)
        var preparedByID: [UUID: ClipboardSearchPreparedDocument] = [:]
        for change in changes {
            let items: [ClipboardItem]
            let usesExistingState: Bool
            switch change {
            case .insert(let item), .updateContent(let item):
                items = [item]
                usesExistingState = true
            case .reset:
                items = currentSnapshot
                usesExistingState = true
            case .updateOCR, .updateSource, .remove, .updateMetadata:
                continue
            }
            for item in items {
                preparedByID[item.id] = try ClipboardSearchPreparedDocument.make(
                    item: item,
                    knownState: usesExistingState ? currentStates[item.id] : nil,
                    assetAccess: assetAccess,
                    checkCancellation: { try cancellationToken.checkCancellation() }
                )
            }
        }
        let newVocabularyTerms = fuzzyTerms(
            in: changes.flatMap { change -> [String] in
                switch change {
                case .insert(let item), .updateContent(let item):
                    let content = preparedByID[item.id]?.content
                    return [content, item.sourceAppDisplayName, item.ocrText].compactMap { $0 }
                case .updateOCR(_, let text):
                    return [text].compactMap { $0 }
                case .updateSource(_, let displayName):
                    return [displayName]
                case .reset:
                    return currentSnapshot.flatMap { item in
                        let content = preparedByID[item.id]?.content
                        return [content, item.sourceAppDisplayName, item.ocrText].compactMap { $0 }
                    }
                case .remove, .updateMetadata:
                    return []
                }
            }
        )
        var workingVocabulary = vocabularyLock.withLock { vocabulary }
        try writeTransaction(
            checkCancellation: { try cancellationToken.checkCancellation() },
            {
                guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
                for change in changes {
                    switch change {
                    case .insert(let item), .updateContent(let item):
                        guard let document = preparedByID[item.id] else { continue }
                        try upsert(document, knownState: currentStates[item.id], connection: writer)
                    case .updateOCR(let itemID, let text):
                        var revision = ClipboardSearchRevisionBuilder()
                        revision.append(tag: 1, value: text ?? "")
                        try executeExpectingSingleChange(
                            "UPDATE documents SET ocr = ?2, ocr_revision = ?3, ocr_length = ?4 WHERE item_id = ?1",
                            values: [
                                .text(itemID.uuidString), .text(text ?? ""), .blob(revision.digest()),
                                .integer(Int64(searchLength(text ?? ""))),
                            ],
                            connection: writer,
                            operation: "update OCR"
                        )
                    case .updateSource(let itemID, let displayName):
                        var revision = ClipboardSearchRevisionBuilder()
                        revision.append(tag: 1, value: displayName)
                        try executeExpectingSingleChange(
                            "UPDATE documents SET source = ?2, source_revision = ?3, source_length = ?4 WHERE item_id = ?1",
                            values: [
                                .text(itemID.uuidString), .text(displayName), .blob(revision.digest()),
                                .integer(Int64(searchLength(displayName))),
                            ],
                            connection: writer,
                            operation: "update source"
                        )
                    case .updateMetadata(let item):
                        try updateMetadata(item, connection: writer)
                    case .remove(let itemID):
                        try execute(
                            "DELETE FROM documents WHERE item_id = ?1",
                            values: [.text(itemID.uuidString)],
                            connection: writer,
                            operation: "remove document"
                        )
                    case .reset:
                        try prepareResetKeepIDs(currentSnapshot.map(\.id), connection: writer)
                        try executeRequired(
                            """
                            DELETE FROM documents
                            WHERE NOT EXISTS (
                                SELECT 1 FROM reset_keep_ids keep WHERE keep.item_id = documents.item_id
                            )
                            """,
                            connection: writer,
                            operation: "reset index"
                        )
                        for item in currentSnapshot {
                            guard let document = preparedByID[item.id] else { continue }
                            try upsert(document, knownState: currentStates[item.id], connection: writer)
                        }
                        try executeRequired(
                            "DELETE FROM reset_keep_ids",
                            connection: writer,
                            operation: "clear reset IDs"
                        )
                    }
                }
                if var snapshot = workingVocabulary {
                    if let buildID = snapshot.buildID {
                        try insertPersistentTerms(
                            newVocabularyTerms,
                            buildID: buildID,
                            into: &snapshot.tree,
                            connection: writer
                        )
                    }
                    workingVocabulary = snapshot
                }
                if !newVocabularyTerms.isEmpty {
                    try executeRequired(
                        "UPDATE search_control SET vocabulary_sequence = vocabulary_sequence + 1 WHERE id = 1",
                        connection: writer,
                        operation: "advance vocabulary sequence"
                    )
                    try withStatement(
                        """
                        INSERT OR IGNORE INTO vocabulary_delta(term, first_sequence)
                        SELECT ?1, vocabulary_sequence FROM search_control WHERE id = 1
                        """,
                        connection: writer,
                        operationName: "insert vocabulary delta"
                    ) { statement in
                        for term in newVocabularyTerms.sorted() {
                            sqlite3_reset(statement)
                            sqlite3_clear_bindings(statement)
                            try bind(
                                .text(term), to: statement, index: 1, connection: writer,
                                operation: "bind vocabulary delta"
                            )
                            try requireDone(
                                sqlite3_step(statement),
                                connection: writer,
                                operation: "insert vocabulary delta"
                            )
                        }
                    }
                    if workingVocabulary != nil {
                        try executeRequired(
                            """
                            UPDATE search_control
                            SET applied_vocabulary_sequence = vocabulary_sequence
                            WHERE id = 1
                            """,
                            connection: writer,
                            operation: "advance applied vocabulary sequence"
                        )
                    }
                }
                try execute(
                    """
                    UPDATE search_control
                    SET history_revision = ?1, index_generation = index_generation + 1
                    WHERE id = 1
                    """,
                    values: [.integer(Int64(clamping: historyRevision))],
                    connection: writer,
                    operation: "record history revision"
                )
            })
        if var workingVocabulary {
            let committed = try committedState()
            workingVocabulary.appliedDeltaSequence = committed.appliedVocabularySequence
            installVocabularySnapshot(workingVocabulary)
        }
        let shouldCheckCompaction = vocabularyLock.withLock { () -> Bool in
            successfulVocabularyMutations += changes.count
            guard successfulVocabularyMutations >= 500 else { return false }
            successfulVocabularyMutations = 0
            return true
        }
        if shouldCheckCompaction { scheduleVocabularyCompaction() }
        return try pendingAssetCount()
    }

    private func prepareResetKeepIDs(_ ids: [UUID], connection: OpaquePointer) throws {
        try executeRequired(
            "CREATE TEMP TABLE IF NOT EXISTS reset_keep_ids(item_id TEXT PRIMARY KEY) WITHOUT ROWID",
            connection: connection,
            operation: "create reset IDs"
        )
        try executeRequired("DELETE FROM reset_keep_ids", connection: connection, operation: "reset keep IDs")
        try withStatement(
            "INSERT OR IGNORE INTO reset_keep_ids(item_id) VALUES(?1)",
            connection: connection,
            operationName: "insert reset ID"
        ) { statement in
            for id in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(
                    .text(id.uuidString),
                    to: statement,
                    index: 1,
                    connection: connection,
                    operation: "bind reset ID"
                )
                try requireDone(sqlite3_step(statement), connection: connection, operation: "insert reset ID")
            }
        }
    }

    func recordIndexedHistoryRevision(_ historyRevision: UInt64) throws {
        try writeTransaction {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            try execute(
                """
                UPDATE search_control
                SET history_revision = ?1, index_generation = index_generation + 1
                WHERE id = 1
                """,
                values: [.integer(Int64(clamping: historyRevision))],
                connection: writer,
                operation: "record history revision"
            )
        }
    }

    func beginIndexing(historyRevision: UInt64) throws {
        try writeTransaction {
            guard let writer else {
                throw ClipboardSearchServiceError.openDatabase("Missing writer")
            }
            try execute(
                "UPDATE search_control SET history_revision = ?1 WHERE id = 1 AND history_revision != ?1",
                values: [.integer(Int64(clamping: historyRevision))],
                connection: writer,
                operation: "record indexing target revision"
            )
        }
    }

    func prepareIndexGeneration(_ generation: UInt64) throws {
        let base = generation == 0 ? 0 : generation - 1
        try writeTransaction {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            try execute(
                "UPDATE search_control SET index_generation = ?1 WHERE id = 1",
                values: [.integer(Int64(clamping: base))],
                connection: writer,
                operation: "prepare index generation"
            )
        }
    }

    func committedState() throws -> ClipboardSearchCommittedState {
        try readerLock.withLock {
            guard let reader else { throw ClipboardSearchServiceError.openDatabase("Missing reader") }
            return try committedState(connection: reader)
        }
    }

    private func committedState(connection: OpaquePointer) throws -> ClipboardSearchCommittedState {
        try withStatement(
            """
            SELECT index_generation, history_revision, vocabulary_generation,
                   applied_vocabulary_sequence
            FROM search_control WHERE id = 1
            """,
            connection: connection,
            operationName: "read committed search state"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "read committed search state")
            return ClipboardSearchCommittedState(
                indexGeneration: UInt64(clamping: sqlite3_column_int64(statement, 0)),
                historyRevision: UInt64(clamping: sqlite3_column_int64(statement, 1)),
                vocabularyGeneration: UInt64(clamping: sqlite3_column_int64(statement, 2)),
                appliedVocabularySequence: UInt64(clamping: sqlite3_column_int64(statement, 3))
            )
        }
    }

    func searchableText(for itemID: UUID) throws -> String? {
        try readerLock.withLock {
            guard let reader else { throw ClipboardSearchServiceError.openDatabase("Missing reader") }
            return try withStatement(
                "SELECT CASE WHEN content = '' THEN ocr ELSE content END FROM documents WHERE item_id = ?1",
                connection: reader,
                operationName: "read searchable text"
            ) { statement in
                try bind(
                    .text(itemID.uuidString), to: statement, index: 1, connection: reader, operation: "bind item ID")
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return nil }
                try requireRow(code, connection: reader, operation: "read searchable text")
                return columnText(statement, 0)
            }
        }
    }

    func prewarmVocabulary() throws {
        let token = ClipboardSearchCancellationToken()
        let input = try vocabularyBuildInput(cancellationToken: token)
        var working = ClipboardPersistentFuzzyVocabulary()
        var resultingState: ClipboardSearchCommittedState?
        var resultingBuildID: String?
        try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            let activeBuildID = try activeVocabularyBuildID(connection: writer)
            let persisted = try persistedVocabularyNodes(connection: writer)
            if let activeBuildID,
                persisted.count == input.terms.count,
                Set(persisted.map(\.term)) == Set(input.terms.map(\.term))
            {
                working = ClipboardPersistentFuzzyVocabulary(persistedNodes: persisted)
                try executeRequired("BEGIN IMMEDIATE", connection: writer, operation: "begin vocabulary catch-up")
                do {
                    try replayVocabularyDeltas(
                        after: input.baseSequence,
                        buildID: activeBuildID,
                        into: &working,
                        connection: writer
                    )
                    try executeRequired(
                        """
                        UPDATE search_control
                        SET applied_vocabulary_sequence = vocabulary_sequence
                        WHERE id = 1
                        """,
                        connection: writer,
                        operation: "record vocabulary catch-up"
                    )
                    try executeRequired(
                        "DELETE FROM vocabulary_delta",
                        connection: writer,
                        operation: "consume vocabulary catch-up deltas"
                    )
                    try executeRequired("COMMIT", connection: writer, operation: "commit vocabulary catch-up")
                    resultingState = try committedState(connection: writer)
                    resultingBuildID = activeBuildID
                } catch {
                    _ = sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
                    throw error
                }
                return
            }
            let buildID = UUID().uuidString
            try executeRequired("BEGIN IMMEDIATE", connection: writer, operation: "begin vocabulary rebuild")
            do {
                try execute(
                    """
                    INSERT INTO vocabulary_build(build_id, base_sequence, state)
                    VALUES(?1, ?2, 0)
                    """,
                    values: [
                        .text(buildID),
                        .integer(Int64(clamping: input.baseSequence)),
                    ],
                    connection: writer,
                    operation: "create vocabulary build"
                )
                working = ClipboardPersistentFuzzyVocabulary()
                try insertPersistentTerms(
                    input.terms.map(\.term),
                    buildID: buildID,
                    frequencies: Dictionary(uniqueKeysWithValues: input.terms),
                    into: &working,
                    connection: writer
                )
                try replayVocabularyDeltas(
                    after: input.baseSequence,
                    buildID: buildID,
                    into: &working,
                    connection: writer
                )
                try execute(
                    "UPDATE vocabulary_build SET state = 2 WHERE build_id <> ?1",
                    values: [.text(buildID)],
                    connection: writer,
                    operation: "retire vocabulary builds"
                )
                try execute(
                    "UPDATE vocabulary_build SET state = 1 WHERE build_id = ?1",
                    values: [.text(buildID)],
                    connection: writer,
                    operation: "activate vocabulary build"
                )
                try execute(
                    """
                    UPDATE search_control SET
                        vocabulary_generation = vocabulary_generation + 1,
                        applied_vocabulary_sequence = vocabulary_sequence,
                        active_vocabulary_build_id = ?1
                    WHERE id = 1
                    """,
                    values: [.text(buildID)],
                    connection: writer,
                    operation: "advance vocabulary generation"
                )
                try executeRequired(
                    "DELETE FROM vocabulary_delta",
                    connection: writer,
                    operation: "consume vocabulary deltas"
                )
                try executeRequired("COMMIT", connection: writer, operation: "commit vocabulary rebuild")
                resultingState = try committedState(connection: writer)
                resultingBuildID = buildID
            } catch {
                _ = sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
                throw error
            }
        }
        guard let resultingState else {
            throw ClipboardSearchServiceError.openDatabase("Missing committed vocabulary state")
        }
        installVocabularySnapshot(
            VocabularySnapshot(
                tree: working,
                buildID: resultingBuildID,
                generation: resultingState.vocabularyGeneration,
                appliedDeltaSequence: resultingState.appliedVocabularySequence
            )
        )
    }

    var isVocabularyLoaded: Bool {
        vocabularyLock.withLock { vocabulary != nil }
    }

    enum SearchPhase: Sendable {
        case strict
        case substring
        case similar
        case complete
    }

    func search(
        query: ClipboardQuery,
        cancellationToken: ClipboardSearchCancellationToken,
        includeFuzzy: Bool = true,
        sessionID: ClipboardSearchSessionID = ClipboardSearchSessionID(),
        phase: SearchPhase = .complete,
        excluding excludedItemIDs: Set<UUID> = []
    ) throws -> (state: ClipboardSearchCommittedState, hits: [ClipboardSearchHit]) {
        try cancellationToken.checkCancellation()
        return try readerLock.withLock {
            try cancellationToken.checkCancellation()
            guard let reader else { throw ClipboardSearchServiceError.openDatabase("Missing reader") }
            let plan = try queryPlan(for: query.text, connection: reader)
            let context = Unmanaged.passUnretained(cancellationToken).toOpaque()
            sqlite3_progress_handler(reader, 2_000, clipboardSearchProgressCallback, context)
            defer { sqlite3_progress_handler(reader, 0, nil, nil) }
            try beginReadSnapshot(connection: reader, operation: "begin search snapshot")
            do {
                let state = try committedState(connection: reader)
                let hits = try withExtendedLifetime(cancellationToken) {
                    try search(
                        plan: plan,
                        query: query,
                        cancellationToken: cancellationToken,
                        includeFuzzy: includeFuzzy,
                        sessionID: sessionID,
                        phase: phase,
                        excludedItemIDs: excludedItemIDs,
                        connection: reader
                    )
                }
                // A cancelled progress callback must not be allowed to interrupt
                // COMMIT/ROLLBACK and leave this reusable reader in a transaction.
                sqlite3_progress_handler(reader, 0, nil, nil)
                try cancellationToken.checkCancellation()
                try executeRequired("COMMIT", connection: reader, operation: "commit search snapshot")
                return (state, hits)
            } catch {
                sqlite3_progress_handler(reader, 0, nil, nil)
                rollbackReadSnapshot(connection: reader)
                throw error
            }
        }
    }

    private func search(
        plan: ClipboardQueryPlan,
        query: ClipboardQuery,
        cancellationToken: ClipboardSearchCancellationToken,
        includeFuzzy: Bool,
        sessionID: ClipboardSearchSessionID,
        phase: SearchPhase,
        excludedItemIDs: Set<UUID>,
        connection reader: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        guard !plan.normalizedPhrase.isEmpty else { return [] }
        try prepareQueryExclusions(excluding: excludedItemIDs, connection: reader)
        defer {
            bestEffortClearTemporaryTable(.excludedDocuments, connection: reader)
        }
        let eligibleCount = try eligibleDocumentCount(filters: query.filters, connection: reader)
        guard eligibleCount > 0 else { return [] }
        var bestByID: [UUID: ClipboardSearchHit] = [:]
        var hasFullCoverage = false
        let runsStrict = phase == .strict || phase == .complete
        let runsSubstring = phase == .substring || phase == .complete
        let runsSimilar = phase == .similar || phase == .complete

        if runsStrict, plan.prefersLiteralPhrase, plan.normalizedPhrase.count >= 3 {
            try cancellationToken.checkCancellation()
            for field in searchableFields(includesOCR: query.includesOCRText) {
                let hits = try phraseHits(
                    phrase: plan.normalizedPhrase,
                    field: field,
                    query: query,
                    sessionID: sessionID,
                    kind: .literalPhrase,
                    tier: .literalPhrase,
                    eligibleCount: eligibleCount,
                    connection: reader
                )
                if bestByID.isEmpty, hits.count == eligibleCount {
                    return hits.sorted(by: hitPrecedes)
                }
                for hit in hits { merge(hit, into: &bestByID) }
                if bestByID.count == eligibleCount {
                    hasFullCoverage = true
                    break
                }
                try excludeFromLowerRankingStages(hits, connection: reader)
            }
        }

        if runsStrict, !hasFullCoverage {
            try cancellationToken.checkCancellation()
            for field in searchableFields(includesOCR: query.includesOCRText) {
                let hits = try exactWordHits(
                    terms: plan.normalizedTerms,
                    field: field,
                    query: query,
                    sessionID: sessionID,
                    eligibleCount: eligibleCount,
                    connection: reader
                )
                if bestByID.isEmpty, hits.count == eligibleCount {
                    return hits.sorted(by: hitPrecedes)
                }
                for hit in hits { merge(hit, into: &bestByID) }
                if bestByID.count == eligibleCount {
                    hasFullCoverage = true
                    break
                }
                try excludeFromLowerRankingStages(hits, connection: reader)
            }
        }

        if runsStrict, !hasFullCoverage {
            try cancellationToken.checkCancellation()
            for field in searchableFields(includesOCR: query.includesOCRText) {
                let hits = try prefixHits(
                    terms: plan.normalizedTerms,
                    field: field,
                    query: query,
                    sessionID: sessionID,
                    eligibleCount: eligibleCount,
                    connection: reader
                )
                for hit in hits { merge(hit, into: &bestByID) }
                if bestByID.count == eligibleCount {
                    hasFullCoverage = true
                    break
                }
                try excludeFromLowerRankingStages(hits, connection: reader)
            }
        }

        if runsSubstring, !hasFullCoverage, plan.normalizedPhrase.count >= 3 {
            try cancellationToken.checkCancellation()
            let substringTerms = plan.normalizedTerms.filter { $0.count >= 3 }
            if !substringTerms.isEmpty {
                for field in searchableFields(includesOCR: query.includesOCRText) {
                    let hits = try substringHits(
                        terms: substringTerms,
                        field: field,
                        query: query,
                        sessionID: sessionID,
                        eligibleCount: eligibleCount,
                        connection: reader
                    )
                    for hit in hits { merge(hit, into: &bestByID) }
                    if bestByID.count == eligibleCount {
                        hasFullCoverage = true
                        break
                    }
                    try excludeFromLowerRankingStages(hits, connection: reader)
                }
            }
        }

        if runsSimilar,
            includeFuzzy,
            !hasFullCoverage,
            plan.allowsFuzzyMatching,
            plan.normalizedTerms.count <= 8,
            plan.normalizedPhrase.count <= 256
        {
            try cancellationToken.checkCancellation()
            for field in searchableFields(includesOCR: query.includesOCRText) {
                let groups = try fuzzyGroups(
                    for: plan.normalizedTerms,
                    field: field,
                    eligibleDocumentCount: eligibleCount,
                    connection: reader,
                    cancellationToken: cancellationToken
                )
                if groups.allSatisfy({ !$0.isEmpty }) {
                    try populateQueryTerms(groups, connection: reader)
                    defer {
                        bestEffortClearTemporaryTable(.terms, connection: reader)
                    }
                    try cancellationToken.checkCancellation()
                    let hits = try fuzzyHits(
                        groups: groups,
                        queryTerms: plan.normalizedTerms,
                        field: field,
                        query: query,
                        sessionID: sessionID,
                        eligibleCount: eligibleCount,
                        connection: reader
                    )
                    for hit in hits { merge(hit, into: &bestByID) }
                    if bestByID.count == eligibleCount { break }
                    try excludeFromLowerRankingStages(hits, connection: reader)
                }
            }
        }

        try cancellationToken.checkCancellation()
        return bestByID.values.sorted(by: hitPrecedes)
    }

    func snippets(
        for hits: [ClipboardSearchHit],
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> (state: ClipboardSearchCommittedState, snippets: [UUID: ClipboardSearchSnippet]) {
        try cancellationToken.checkCancellation()
        let requested = Array(hits.prefix(50))
        return try snippetReaderLock.withLock {
            try cancellationToken.checkCancellation()
            guard let reader = snippetReader else {
                throw ClipboardSearchServiceError.openDatabase("Missing snippet reader")
            }
            let context = Unmanaged.passUnretained(cancellationToken).toOpaque()
            sqlite3_progress_handler(reader, 2_000, clipboardSearchProgressCallback, context)
            defer { sqlite3_progress_handler(reader, 0, nil, nil) }
            try beginReadSnapshot(connection: reader, operation: "begin snippet snapshot")
            do {
                let state = try committedState(connection: reader)
                let snippets = try withExtendedLifetime(cancellationToken) {
                    var result: [UUID: ClipboardSearchSnippet] = [:]
                    for hit in requested where hit.evidence.field != .sourceApplication {
                        try cancellationToken.checkCancellation()
                        let column = hit.evidence.field == .ocr ? "ocr" : "content"
                        let matchedTerms = hit.evidence.terms.map(\.normalizedMatchedTerm)
                        let phrase =
                            hit.evidence.kind == .literalPhrase
                            ? matchedTerms.joined(separator: " ") : nil
                        let needles = ([phrase].compactMap { $0 } + matchedTerms).filter {
                            !$0.isEmpty
                        }
                        let ftsText = try ftsSnippetWindow(for: hit, connection: reader)
                        var snippet = ftsText.flatMap {
                            makeSnippet(
                                text: $0,
                                phrase: phrase,
                                terms: matchedTerms,
                                sessionID: hit.evidence.sessionID,
                                field: hit.evidence.field
                            )
                        }
                        if snippet == nil,
                            let literalText = try boundedSnippetWindow(
                                itemID: hit.itemID,
                                column: column,
                                needles: needles,
                                connection: reader
                            )
                        {
                            snippet = makeSnippet(
                                text: literalText,
                                phrase: phrase,
                                terms: matchedTerms,
                                sessionID: hit.evidence.sessionID,
                                field: hit.evidence.field
                            )
                        }
                        guard let snippet else { continue }
                        result[hit.itemID] = snippet
                    }
                    return result
                }
                sqlite3_progress_handler(reader, 0, nil, nil)
                try cancellationToken.checkCancellation()
                try executeRequired("COMMIT", connection: reader, operation: "commit snippet snapshot")
                return (state, snippets)
            } catch {
                sqlite3_progress_handler(reader, 0, nil, nil)
                rollbackReadSnapshot(connection: reader)
                throw error
            }
        }
    }

    private func boundedSnippetWindow(
        itemID: UUID,
        column: String,
        needles: [String],
        connection: OpaquePointer
    ) throws -> String? {
        // The column name is selected from the two internal constants above. A
        // 126-character window plus two ellipses is at most 510 UTF-8 bytes and prevents a large
        // external-content value from ever becoming a full Swift String.
        let sql = """
            WITH matched(value, position) AS (
                SELECT \(column), instr(lower(\(column)), lower(?1))
                FROM documents
                WHERE item_id = ?2
            )
            SELECT
                CASE WHEN position > 61 THEN '…' ELSE '' END
                || substr(value, MAX(1, position - 59), 126)
                || CASE
                    WHEN length(value) > MAX(1, position - 59) + 125 THEN '…'
                    ELSE ''
                   END
            FROM matched
            WHERE position > 0
            """
        for needle in needles {
            let text: String? = try withStatement(
                sql,
                connection: connection,
                operationName: "load bounded snippet window"
            ) { statement in
                try bind(
                    .text(needle), to: statement, index: 1, connection: connection,
                    operation: "bind snippet needle"
                )
                try bind(
                    .text(itemID.uuidString), to: statement, index: 2, connection: connection,
                    operation: "bind snippet ID"
                )
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return nil }
                try requireRow(code, connection: connection, operation: "load bounded snippet window")
                return columnText(statement, 0)
            }
            if let text { return text }
        }
        return nil
    }

    private func ftsSnippetWindow(
        for hit: ClipboardSearchHit,
        connection: OpaquePointer
    ) throws -> String? {
        let table: String
        switch hit.evidence.field {
        case .content:
            table = "content_trigram"
        case .ocr:
            table = "ocr_trigram"
        case .sourceApplication:
            return nil
        }

        let expression: String
        switch hit.evidence.kind {
        case .literalPhrase:
            expression = quotedFTS(
                hit.evidence.terms.map(\.normalizedMatchedTerm).joined(separator: " ")
            )
        case .substring:
            expression = hit.evidence.terms.map {
                quotedFTS($0.normalizedMatchedTerm)
            }.joined(separator: " AND ")
        case .prefix:
            expression = hit.evidence.terms.map {
                quotedFTS($0.normalizedQueryTerm) + "*"
            }.joined(separator: " AND ")
        case .exactToken, .fuzzyCorrection:
            expression = hit.evidence.terms.map {
                quotedFTS($0.normalizedMatchedTerm)
            }.joined(separator: " AND ")
        }
        guard !expression.isEmpty else { return nil }

        return try withStatement(
            """
            SELECT substr(snippet(\(table), 0, '', '', '…', 16), 1, 126)
            FROM \(table)
            JOIN documents d ON d.rowid = \(table).rowid
            WHERE \(table) MATCH ?1 AND d.item_id = ?2
            """,
            connection: connection,
            operationName: "load bounded FTS snippet window"
        ) { statement in
            try bind(
                .text(expression), to: statement, index: 1, connection: connection,
                operation: "bind FTS snippet expression"
            )
            try bind(
                .text(hit.itemID.uuidString), to: statement, index: 2, connection: connection,
                operation: "bind FTS snippet ID"
            )
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return nil }
            try requireRow(code, connection: connection, operation: "load bounded FTS snippet window")
            return columnText(statement, 0)
        }
    }

    private struct SearchField {
        let trigramTable: String
        let trigramVocabularyTable: String
        let wordTable: String
        let rowVocabularyTable: String
        let instanceTable: String
        let lengthColumn: String
        let lengthSumColumn: String
        let field: ClipboardMatchField
        let priority: ClipboardSearchFieldPriority
    }

    private struct FuzzyCandidate: Sendable {
        let editDistance: Int
        let weightedCost: Double
        let quality: Double
    }

    private struct FuzzyDocumentMatch: Sendable {
        let terms: [ClipboardSearchTermEvidence]
        let totalEditDistance: Int
        let correctionQuality: Double
    }

    private func searchableFields(includesOCR: Bool) -> [SearchField] {
        var result = [
            SearchField(
                trigramTable: "content_trigram",
                trigramVocabularyTable: "content_trigram_rows",
                wordTable: "content_word",
                rowVocabularyTable: "content_word_rows",
                instanceTable: "content_word_instances",
                lengthColumn: "content_length",
                lengthSumColumn: "content_length_sum",
                field: .content,
                priority: .content
            )
        ]
        if includesOCR {
            result.append(
                SearchField(
                    trigramTable: "ocr_trigram",
                    trigramVocabularyTable: "ocr_trigram_rows",
                    wordTable: "ocr_word",
                    rowVocabularyTable: "ocr_word_rows",
                    instanceTable: "ocr_word_instances",
                    lengthColumn: "ocr_length",
                    lengthSumColumn: "ocr_length_sum",
                    field: .ocr,
                    priority: .ocr
                )
            )
        }
        result.append(
            SearchField(
                trigramTable: "source_trigram",
                trigramVocabularyTable: "source_trigram_rows",
                wordTable: "source_word",
                rowVocabularyTable: "source_word_rows",
                instanceTable: "source_word_instances",
                lengthColumn: "source_length",
                lengthSumColumn: "source_length_sum",
                field: .sourceApplication,
                priority: .sourceApplication
            )
        )
        return result
    }

    private func phraseHits(
        phrase: String,
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        kind: ClipboardSearchMatchKind,
        tier: ClipboardSearchMatchTier,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        let computesBM25 = try shouldComputeBM25ForPhrase(
            phrase: phrase,
            field: field,
            connection: connection
        )
        var values: [SQLiteValue] = [.text(quotedFTS(phrase))]
        let filter = filterSQL(query.filters, values: &values)
        let sql = """
            SELECT d.item_id,
                   \(computesBM25 ? "bm25(\(field.trigramTable))" : "0.0") AS search_rank,
                   m.copied_at, d.\(field.lengthColumn)
            FROM \(field.trigramTable)
            JOIN documents d ON d.rowid = \(field.trigramTable).rowid
            JOIN search_metadata m ON m.document_id = d.rowid
            WHERE \(field.trigramTable) MATCH ?1 \(filter)
              AND NOT EXISTS (
                  SELECT 1 FROM query_excluded_documents excluded
                  WHERE excluded.item_id = d.item_id
              )
            ORDER BY search_rank ASC, m.copied_at DESC, d.item_id ASC
            """
        return try queryHits(
            sql: sql,
            values: values,
            field: field,
            sessionID: sessionID,
            kind: kind,
            tier: tier,
            fuzzyMatches: [:],
            queryTerms: [phrase],
            relevanceMethod: computesBM25 ? .ftsBM25 : .boundedIDFLengthV1,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func exactWordHits(
        terms: [String],
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        try wordHits(
            terms: terms,
            usesPrefix: false,
            field: field,
            query: query,
            sessionID: sessionID,
            kind: .exactToken,
            tier: .exactToken,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func prefixHits(
        terms: [String],
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        try wordHits(
            terms: terms,
            usesPrefix: true,
            field: field,
            query: query,
            sessionID: sessionID,
            kind: .prefix,
            tier: .prefix,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func wordHits(
        terms: [String],
        usesPrefix: Bool,
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        kind: ClipboardSearchMatchKind,
        tier: ClipboardSearchMatchTier,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        guard !terms.isEmpty else { return [] }
        let expression = terms.map { term in
            usesPrefix ? "\(quotedFTS(term))*" : quotedFTS(term)
        }.joined(separator: " AND ")
        guard expression.utf8.count <= 32 * 1_024 else { return [] }
        // Prefix posting lists can contain millions of repeated occurrences in
        // large documents. Ranking those with bm25() would force FTS to visit
        // occurrence detail that membership does not need. The bounded ranker
        // uses the maintained field lengths and keeps this path proportional to
        // the returned documents.
        let computesBM25: Bool
        if usesPrefix {
            computesBM25 = false
        } else {
            computesBM25 = try postingWorkIsBounded(
                exactTerms: terms,
                table: field.rowVocabularyTable,
                connection: connection
            )
        }
        var values: [SQLiteValue] = [.text(expression)]
        let filter = filterSQL(query.filters, values: &values)
        let sql = """
            SELECT d.item_id,
                   \(computesBM25 ? "bm25(\(field.wordTable))" : "0.0") AS search_rank,
                   m.copied_at, d.\(field.lengthColumn)
            FROM \(field.wordTable)
            JOIN documents d ON d.rowid = \(field.wordTable).rowid
            JOIN search_metadata m ON m.document_id = d.rowid
            WHERE \(field.wordTable) MATCH ?1 \(filter)
              AND NOT EXISTS (
                  SELECT 1 FROM query_excluded_documents excluded
                  WHERE excluded.item_id = d.item_id
              )
            ORDER BY search_rank ASC, m.copied_at DESC, d.item_id ASC
            """
        return try queryHits(
            sql: sql,
            values: values,
            field: field,
            sessionID: sessionID,
            kind: kind,
            tier: tier,
            fuzzyMatches: [:],
            queryTerms: terms,
            relevanceMethod: computesBM25 ? .ftsBM25 : .boundedIDFLengthV1,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func substringHits(
        terms: [String],
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        guard !terms.isEmpty else { return [] }
        let expression = terms.map(quotedFTS).joined(separator: " AND ")
        guard expression.utf8.count <= 32 * 1_024 else { return [] }
        let computesBM25 = try terms.allSatisfy { term in
            try shouldComputeBM25ForPhrase(
                phrase: term,
                field: field,
                connection: connection
            )
        }
        var values: [SQLiteValue] = [.text(expression)]
        let filter = filterSQL(query.filters, values: &values)
        let sql = """
            SELECT d.item_id,
                   \(computesBM25 ? "bm25(\(field.trigramTable))" : "0.0") AS search_rank,
                   m.copied_at, d.\(field.lengthColumn)
            FROM \(field.trigramTable)
            JOIN documents d ON d.rowid = \(field.trigramTable).rowid
            JOIN search_metadata m ON m.document_id = d.rowid
            WHERE \(field.trigramTable) MATCH ?1 \(filter)
              AND NOT EXISTS (
                  SELECT 1 FROM query_excluded_documents excluded
                  WHERE excluded.item_id = d.item_id
              )
            ORDER BY search_rank ASC, m.copied_at DESC, d.item_id ASC
            """
        return try queryHits(
            sql: sql,
            values: values,
            field: field,
            sessionID: sessionID,
            kind: .substring,
            tier: .substring,
            fuzzyMatches: [:],
            queryTerms: terms,
            relevanceMethod: computesBM25 ? .ftsBM25 : .boundedIDFLengthV1,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func fuzzyHits(
        groups: [[String: FuzzyCandidate]],
        queryTerms: [String],
        field: SearchField,
        query: ClipboardQuery,
        sessionID: ClipboardSearchSessionID,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        let uniformMatch = uniformFuzzyMatch(groups: groups, queryTerms: queryTerms)
        let distances: [UUID: FuzzyDocumentMatch]
        if uniformMatch == nil {
            distances = try fuzzyDistances(
                termCount: groups.count,
                instanceTable: field.instanceTable,
                query: query,
                connection: connection
            )
            guard !distances.isEmpty else { return [] }
        } else {
            distances = [:]
        }
        let expression = groups.map { group in
            "(" + group.keys.sorted().map(quotedFTS).joined(separator: " OR ") + ")"
        }.joined(separator: " AND ")
        guard expression.utf8.count <= 32 * 1_024 else { return [] }
        var values: [SQLiteValue] = [.text(expression)]
        let filter = filterSQL(query.filters, values: &values)
        let postingWorkIsSmall = try postingWorkIsBounded(
            exactTerms: groups.flatMap { $0.keys },
            table: field.rowVocabularyTable,
            connection: connection
        )
        let computesBM25 = (uniformMatch != nil || distances.count <= 2_048) && postingWorkIsSmall
        let sql = """
            SELECT d.item_id, \(computesBM25 ? "bm25(\(field.wordTable))" : "0.0"),
                   m.copied_at, d.\(field.lengthColumn)
            FROM \(field.wordTable)
            JOIN documents d ON d.rowid = \(field.wordTable).rowid
            JOIN search_metadata m ON m.document_id = d.rowid
            WHERE \(field.wordTable) MATCH ?1 \(filter)
              AND NOT EXISTS (
                  SELECT 1 FROM query_excluded_documents excluded
                  WHERE excluded.item_id = d.item_id
              )
            """
        return try queryHits(
            sql: sql,
            values: values,
            field: field,
            sessionID: sessionID,
            kind: .fuzzyCorrection,
            tier: .fuzzy,
            fuzzyMatches: distances,
            uniformFuzzyMatch: uniformMatch,
            queryTerms: [],
            relevanceMethod: computesBM25 ? .ftsBM25 : .boundedIDFLengthV1,
            eligibleCount: eligibleCount,
            connection: connection
        )
    }

    private func queryHits(
        sql: String,
        values: [SQLiteValue],
        field: SearchField,
        sessionID: ClipboardSearchSessionID,
        kind: ClipboardSearchMatchKind,
        tier: ClipboardSearchMatchTier,
        fuzzyMatches: [UUID: FuzzyDocumentMatch],
        uniformFuzzyMatch: FuzzyDocumentMatch? = nil,
        queryTerms: [String],
        relevanceMethod: ClipboardSearchRelevanceMethod,
        eligibleCount: Int,
        connection: OpaquePointer
    ) throws -> [ClipboardSearchHit] {
        struct RawHit {
            let id: UUID
            let distance: Int
            let score: Double
            let copiedAt: Double
            let documentLength: Int
        }
        var rawHits: [RawHit] = []
        try withStatement(sql, connection: connection, operationName: "search \(field.wordTable)") { statement in
            try bind(values, to: statement, connection: connection, operation: "bind search")
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                try requireRow(code, connection: connection, operation: "search \(field.wordTable)")
                guard let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)) else { continue }
                let distance: Int
                if kind == .fuzzyCorrection {
                    guard let value = fuzzyMatches[id] ?? uniformFuzzyMatch else { continue }
                    distance = value.totalEditDistance
                } else {
                    distance = 0
                }
                rawHits.append(
                    RawHit(
                        id: id,
                        distance: distance,
                        score: sqlite3_column_double(statement, 1),
                        copiedAt: sqlite3_column_double(statement, 2),
                        documentLength: Int(sqlite3_column_int64(statement, 3))
                    )
                )
            }
        }
        let averageLength = try averageLength(for: field, connection: connection)
        let hitCount = rawHits.count
        let boundedIDF = log(
            1 + (Double(max(0, eligibleCount - hitCount)) + 0.5) / (Double(hitCount) + 0.5)
        )
        return rawHits.map { raw in
            let score: Double
            if relevanceMethod == .ftsBM25 {
                score = raw.score
            } else {
                let normalization =
                    0.25
                    + 0.75 * Double(max(1, raw.documentLength)) / Double(max(1, averageLength))
                let termCount =
                    kind == .fuzzyCorrection
                    ? (fuzzyMatches[raw.id] ?? uniformFuzzyMatch)?.terms.count ?? 1
                    : queryTerms.count
                score = -(boundedIDF * Double(max(1, termCount))) / normalization
            }
            let terms: [ClipboardSearchTermEvidence]
            let correctionQuality: Double?
            if let fuzzyMatch = fuzzyMatches[raw.id] ?? uniformFuzzyMatch {
                terms = fuzzyMatch.terms
                correctionQuality = fuzzyMatch.correctionQuality
            } else {
                terms = queryTerms.enumerated().map { index, term in
                    ClipboardSearchTermEvidence(
                        queryTermIndex: index,
                        normalizedQueryTerm: term,
                        normalizedMatchedTerm: term,
                        editDistance: 0,
                        weightedEditCost: 0
                    )
                }
                correctionQuality = nil
            }
            return ClipboardSearchHit(
                itemID: raw.id,
                region: kind == .fuzzyCorrection ? .similar : .strict,
                rank: ClipboardSearchRank(
                    tier: tier,
                    fieldPriority: field.priority,
                    editDistance: raw.distance,
                    relevance: ClipboardSearchRelevance(score: score, method: relevanceMethod),
                    copiedAt: raw.copiedAt
                ),
                evidence: ClipboardSearchMatchEvidence(
                    sessionID: sessionID,
                    field: field.field,
                    kind: kind,
                    terms: terms,
                    correctionQuality: correctionQuality
                ),
                snippet: nil
            )
        }
    }

    private func shouldComputeBM25ForPhrase(
        phrase: String,
        field: SearchField,
        connection: OpaquePointer
    ) throws -> Bool {
        let characters = Array(phrase)
        guard characters.count >= 3 else { return false }
        let trigrams = Array(
            Set((0...(characters.count - 3)).map { String(characters[$0...($0 + 2)]) })
        ).sorted()
        return try postingWorkIsBounded(
            exactTerms: trigrams,
            table: field.trigramVocabularyTable,
            connection: connection
        )
    }

    private func postingWorkIsBounded(
        exactTerms: [String],
        table: String,
        connection: OpaquePointer
    ) throws -> Bool {
        guard !exactTerms.isEmpty else { return true }
        let uniqueTerms = Array(Set(exactTerms)).sorted()
        let placeholders = uniqueTerms.indices.map { "?\($0 + 1)" }.joined(separator: ",")
        return try withStatement(
            """
            SELECT COALESCE(SUM(cnt), 0), COALESCE(SUM(doc), 0)
            FROM \(table) WHERE term IN (\(placeholders))
            """,
            connection: connection,
            operationName: "estimate exact postings"
        ) { statement in
            for (offset, term) in uniqueTerms.enumerated() {
                try bind(
                    .text(term),
                    to: statement,
                    index: Int32(offset + 1),
                    connection: connection,
                    operation: "bind posting term"
                )
            }
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "estimate exact postings")
            return sqlite3_column_int64(statement, 0) <= 250_000
                && sqlite3_column_int64(statement, 1) <= 512
        }
    }

    private func averageLength(for field: SearchField, connection: OpaquePointer) throws -> Int {
        try withStatement(
            "SELECT \(field.lengthSumColumn), document_count FROM search_control WHERE id = 1",
            connection: connection,
            operationName: "read average field length"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "read average field length")
            let sum = sqlite3_column_int64(statement, 0)
            let count = max(1, sqlite3_column_int64(statement, 1))
            return Int(max(1, sum / count))
        }
    }

    private func eligibleDocumentCount(
        filters: ClipboardFilters,
        connection: OpaquePointer
    ) throws -> Int {
        var values: [SQLiteValue] = []
        let filter = filterSQL(filters, values: &values)
        return try withStatement(
            "SELECT COUNT(*) FROM search_metadata m WHERE 1 = 1 \(filter)",
            connection: connection,
            operationName: "count eligible documents"
        ) { statement in
            try bind(values, to: statement, connection: connection, operation: "bind eligibility filters")
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "count eligible documents")
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private func prepareQueryExclusions(
        excluding itemIDs: Set<UUID> = [],
        connection: OpaquePointer
    ) throws {
        try executeRequired(
            """
            CREATE TEMP TABLE IF NOT EXISTS query_excluded_documents(
                item_id TEXT PRIMARY KEY
            ) WITHOUT ROWID
            """,
            connection: connection,
            operation: "create query exclusions"
        )
        try executeRequired(
            "DELETE FROM query_excluded_documents",
            connection: connection,
            operation: "reset query exclusions"
        )
        guard !itemIDs.isEmpty else { return }
        try withStatement(
            "INSERT OR IGNORE INTO query_excluded_documents(item_id) VALUES(?1)",
            connection: connection,
            operationName: "seed query exclusions"
        ) { statement in
            for itemID in itemIDs {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(
                    .text(itemID.uuidString), to: statement, index: 1,
                    connection: connection, operation: "bind seeded exclusion"
                )
                try requireDone(
                    sqlite3_step(statement), connection: connection,
                    operation: "seed query exclusion"
                )
            }
        }
    }

    private func excludeFromLowerRankingStages(
        _ hits: [ClipboardSearchHit],
        connection: OpaquePointer
    ) throws {
        guard !hits.isEmpty else { return }
        try withStatement(
            "INSERT OR IGNORE INTO query_excluded_documents(item_id) VALUES(?1)",
            connection: connection,
            operationName: "exclude ranked document"
        ) { statement in
            for hit in hits {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                try bind(
                    .text(hit.itemID.uuidString),
                    to: statement,
                    index: 1,
                    connection: connection,
                    operation: "bind excluded document"
                )
                try requireDone(
                    sqlite3_step(statement),
                    connection: connection,
                    operation: "exclude ranked document"
                )
            }
        }
    }

    private func fuzzyGroups(
        for terms: [String],
        field: SearchField,
        eligibleDocumentCount: Int,
        connection: OpaquePointer,
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> [[String: FuzzyCandidate]] {
        let perTermBudget = min(
            ClipboardFuzzyPolicyV2.maximumCandidatesPerTerm,
            max(1, ClipboardFuzzyPolicyV2.maximumCandidatesPerQuery / max(1, terms.count))
        )
        var groups: [[String: FuzzyCandidate]] = []
        var vocabularyTree: ClipboardPersistentFuzzyVocabulary?
        for term in terms {
            try cancellationToken.checkCancellation()
            let exactFrequency = try documentFrequencies([term], connection: connection)[term, default: 0]
            let hasPrefix = try hasVocabularyPrefix(
                term,
                table: field.rowVocabularyTable,
                connection: connection
            )
            if exactFrequency > 0 || hasPrefix {
                groups.append([
                    term: FuzzyCandidate(editDistance: 0, weightedCost: 0, quality: 1)
                ])
                continue
            }
            guard ClipboardFuzzyPolicyV2.isPotentiallyFuzzy(term),
                !ClipboardFuzzyPolicyV2.isTechnicalToken(term)
            else {
                groups.append([:])
                continue
            }
            let tree: ClipboardPersistentFuzzyVocabulary
            if let vocabularyTree {
                tree = vocabularyTree
            } else {
                let loaded = try loadedVocabulary(
                    connection: connection,
                    cancellationToken: cancellationToken
                )
                vocabularyTree = loaded
                tree = loaded
            }
            let candidates = tree.candidates(
                for: term,
                maximumDistance: ClipboardFuzzyPolicyV2.maximumEditDistance(
                    for: term,
                    field: field.field
                )
            )
            let frequencies = try documentFrequencies(
                candidates.map(\.term),
                table: field.rowVocabularyTable,
                connection: connection
            )
            let selected =
                candidates
                .compactMap { candidate -> (term: String, candidate: FuzzyCandidate)? in
                    let frequency = frequencies[candidate.term, default: 0]
                    guard frequency > 0,
                        let score = ClipboardFuzzyPolicyV2.accepts(
                            query: term,
                            candidate: candidate.term,
                            field: field.field,
                            documentFrequency: frequency,
                            eligibleDocumentCount: eligibleDocumentCount
                        )
                    else { return nil }
                    return (
                        candidate.term,
                        FuzzyCandidate(
                            editDistance: candidate.distance,
                            weightedCost: score.weightedCost,
                            quality: score.quality
                        )
                    )
                }
                .sorted {
                    if $0.candidate.quality != $1.candidate.quality {
                        return $0.candidate.quality > $1.candidate.quality
                    }
                    if $0.candidate.editDistance != $1.candidate.editDistance {
                        return $0.candidate.editDistance < $1.candidate.editDistance
                    }
                    let left = frequencies[$0.term, default: 0]
                    let right = frequencies[$1.term, default: 0]
                    if left != right { return left < right }
                    return $0.term < $1.term
                }
                .prefix(perTermBudget)
            groups.append(Dictionary(uniqueKeysWithValues: selected.map { ($0.term, $0.candidate) }))
        }
        return groups
    }

    private func hasVocabularyPrefix(
        _ prefix: String,
        table: String,
        connection: OpaquePointer
    ) throws -> Bool {
        guard !prefix.isEmpty else { return false }
        let upperBound = prefix + "\u{10FFFF}"
        return try withStatement(
            "SELECT 1 FROM \(table) WHERE term >= ?1 AND term < ?2 LIMIT 1",
            connection: connection,
            operationName: "check vocabulary prefix"
        ) { statement in
            try bind(
                .text(prefix), to: statement, index: 1, connection: connection,
                operation: "bind vocabulary prefix"
            )
            try bind(
                .text(upperBound), to: statement, index: 2, connection: connection,
                operation: "bind vocabulary prefix upper bound"
            )
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return false }
            try requireRow(code, connection: connection, operation: "check vocabulary prefix")
            return true
        }
    }

    private func loadedVocabulary(
        connection: OpaquePointer,
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> ClipboardPersistentFuzzyVocabulary {
        let state = try committedState(connection: connection)
        if let current = vocabularyLock.withLock({ vocabulary }),
            current.generation == state.vocabularyGeneration,
            current.appliedDeltaSequence == state.appliedVocabularySequence
        {
            return current.tree
        }
        let persisted = try persistedVocabularyNodes(connection: connection)
        if !persisted.isEmpty {
            let loaded = ClipboardPersistentFuzzyVocabulary(persistedNodes: persisted)
            installVocabularySnapshot(
                VocabularySnapshot(
                    tree: loaded,
                    buildID: try activeVocabularyBuildID(connection: connection),
                    generation: state.vocabularyGeneration,
                    appliedDeltaSequence: state.appliedVocabularySequence
                )
            )
            return loaded
        }
        let terms = try activeVocabularyTerms(
            connection: connection,
            cancellationToken: cancellationToken
        )
        var built = ClipboardPersistentFuzzyVocabulary()
        for (term, _) in terms { _ = built.insert(term) }
        installVocabularySnapshot(
            VocabularySnapshot(
                tree: built,
                buildID: nil,
                generation: state.vocabularyGeneration,
                appliedDeltaSequence: state.appliedVocabularySequence
            )
        )
        return built
    }

    private func installVocabularySnapshot(_ candidate: VocabularySnapshot) {
        vocabularyLock.withLock {
            if let current = vocabulary {
                guard
                    candidate.generation > current.generation
                        || (candidate.generation == current.generation
                            && candidate.appliedDeltaSequence >= current.appliedDeltaSequence)
                else { return }
            }
            vocabulary = candidate
        }
    }

    private func vocabularyBuildInput(
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> (terms: [(term: String, frequency: Int)], baseSequence: UInt64) {
        try maintenanceReaderLock.withLock {
            guard let maintenanceReader else {
                throw ClipboardSearchServiceError.openDatabase("Missing maintenance reader")
            }
            let context = Unmanaged.passUnretained(cancellationToken).toOpaque()
            sqlite3_progress_handler(
                maintenanceReader, 2_000, clipboardSearchProgressCallback, context
            )
            defer { sqlite3_progress_handler(maintenanceReader, 0, nil, nil) }
            try beginReadSnapshot(
                connection: maintenanceReader, operation: "begin vocabulary snapshot"
            )
            do {
                let baseSequence = try withStatement(
                    "SELECT vocabulary_sequence FROM search_control WHERE id = 1",
                    connection: maintenanceReader,
                    operationName: "read vocabulary base sequence"
                ) { statement in
                    let code = sqlite3_step(statement)
                    try requireRow(
                        code,
                        connection: maintenanceReader,
                        operation: "read vocabulary base sequence"
                    )
                    return UInt64(clamping: sqlite3_column_int64(statement, 0))
                }
                let terms = try activeVocabularyTerms(
                    connection: maintenanceReader,
                    cancellationToken: cancellationToken
                )
                sqlite3_progress_handler(maintenanceReader, 0, nil, nil)
                try cancellationToken.checkCancellation()
                try executeRequired(
                    "COMMIT", connection: maintenanceReader, operation: "commit vocabulary snapshot"
                )
                return (terms, baseSequence)
            } catch {
                sqlite3_progress_handler(maintenanceReader, 0, nil, nil)
                rollbackReadSnapshot(connection: maintenanceReader)
                throw error
            }
        }
    }

    private func replayVocabularyDeltas(
        after baseSequence: UInt64,
        buildID: String,
        into tree: inout ClipboardPersistentFuzzyVocabulary,
        connection: OpaquePointer
    ) throws {
        var terms: [String] = []
        try withStatement(
            """
            SELECT term FROM vocabulary_delta
            WHERE first_sequence > ?1
            ORDER BY first_sequence, term
            """,
            connection: connection,
            operationName: "load vocabulary deltas"
        ) { statement in
            try bind(
                .integer(Int64(clamping: baseSequence)),
                to: statement,
                index: 1,
                connection: connection,
                operation: "bind vocabulary base sequence"
            )
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                try requireRow(code, connection: connection, operation: "load vocabulary deltas")
                if let term = columnText(statement, 0) { terms.append(term) }
                if terms.count > 10_000 { throw CancellationError() }
            }
        }
        try insertPersistentTerms(
            terms,
            buildID: buildID,
            into: &tree,
            connection: connection
        )
    }

    private func persistedVocabularyNodes(
        connection: OpaquePointer
    ) throws -> [ClipboardPersistentFuzzyVocabulary.PersistedNode] {
        guard let buildID = try activeVocabularyBuildID(connection: connection) else {
            return []
        }
        var persisted: [ClipboardPersistentFuzzyVocabulary.PersistedNode] = []
        try withStatement(
            """
            SELECT node_index, term, parent_index, edge_distance
            FROM vocabulary_node
            WHERE build_id = ?1
            ORDER BY node_index
            """,
            connection: connection,
            operationName: "load persisted fuzzy vocabulary"
        ) { statement in
            try bind(
                .text(buildID),
                to: statement,
                index: 1,
                connection: connection,
                operation: "bind active vocabulary build"
            )
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                try requireRow(code, connection: connection, operation: "load persisted fuzzy vocabulary")
                guard let term = columnText(statement, 1) else { continue }
                persisted.append(
                    .init(
                        databaseID: sqlite3_column_int64(statement, 0),
                        term: term,
                        parentDatabaseID: sqlite3_column_type(statement, 2) == SQLITE_NULL
                            ? nil : sqlite3_column_int64(statement, 2),
                        edgeDistance: sqlite3_column_type(statement, 3) == SQLITE_NULL
                            ? nil : Int(sqlite3_column_int(statement, 3))
                    )
                )
            }
        }
        return persisted
    }

    private func activeVocabularyBuildID(connection: OpaquePointer) throws -> String? {
        try withStatement(
            "SELECT active_vocabulary_build_id FROM search_control WHERE id = 1",
            connection: connection,
            operationName: "read active vocabulary build"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "read active vocabulary build")
            return columnText(statement, 0)
        }
    }

    private func activeVocabularyTerms(
        connection: OpaquePointer,
        cancellationToken: ClipboardSearchCancellationToken
    ) throws -> [(term: String, frequency: Int)] {
        var terms: [(String, Int)] = []
        let sql = """
            SELECT term, SUM(doc) FROM (
                SELECT term, doc FROM content_word_rows
                UNION ALL SELECT term, doc FROM source_word_rows
                UNION ALL SELECT term, doc FROM ocr_word_rows
            ) GROUP BY term ORDER BY SUM(doc) DESC, term ASC
            """
        try withStatement(sql, connection: connection, operationName: "load fuzzy vocabulary") { statement in
            var row = 0
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                try requireRow(code, connection: connection, operation: "load fuzzy vocabulary")
                if row.isMultiple(of: 256) { try cancellationToken.checkCancellation() }
                row += 1
                guard let term = columnText(statement, 0), term.count >= 3, term.count <= 64 else { continue }
                terms.append((term, Int(sqlite3_column_int64(statement, 1))))
            }
        }
        return terms
    }

    private func documentFrequencies(
        _ terms: [String],
        connection: OpaquePointer
    ) throws -> [String: Int] {
        guard !terms.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        for start in stride(from: 0, to: terms.count, by: 300) {
            let batch = Array(terms[start..<min(start + 300, terms.count)])
            let placeholders = (0..<batch.count).map { "?\($0 + 1)" }.joined(separator: ",")
            let sql = """
                SELECT term, SUM(doc) FROM (
                    SELECT term, doc FROM content_word_rows WHERE term IN (\(placeholders))
                    UNION ALL SELECT term, doc FROM source_word_rows WHERE term IN (\(placeholders))
                    UNION ALL SELECT term, doc FROM ocr_word_rows WHERE term IN (\(placeholders))
                ) GROUP BY term
                """
            try withStatement(sql, connection: connection, operationName: "read term frequencies") { statement in
                for (offset, term) in batch.enumerated() {
                    try bind(
                        .text(term), to: statement, index: Int32(offset + 1), connection: connection,
                        operation: "bind term")
                }
                while true {
                    let code = sqlite3_step(statement)
                    if code == SQLITE_DONE { break }
                    try requireRow(code, connection: connection, operation: "read term frequencies")
                    if let term = columnText(statement, 0) {
                        result[term] = Int(sqlite3_column_int64(statement, 1))
                    }
                }
            }
        }
        return result
    }

    private func documentFrequencies(
        _ terms: [String],
        table: String,
        connection: OpaquePointer
    ) throws -> [String: Int] {
        guard !terms.isEmpty else { return [:] }
        var result: [String: Int] = [:]
        for start in stride(from: 0, to: terms.count, by: 300) {
            let batch = Array(terms[start..<min(start + 300, terms.count)])
            let placeholders = (0..<batch.count).map { "?\($0 + 1)" }.joined(separator: ",")
            let sql = "SELECT term, doc FROM \(table) WHERE term IN (\(placeholders))"
            try withStatement(sql, connection: connection, operationName: "read field term frequencies") {
                statement in
                for (offset, term) in batch.enumerated() {
                    try bind(
                        .text(term), to: statement, index: Int32(offset + 1),
                        connection: connection, operation: "bind field term"
                    )
                }
                while true {
                    let code = sqlite3_step(statement)
                    if code == SQLITE_DONE { break }
                    try requireRow(
                        code, connection: connection, operation: "read field term frequencies")
                    if let term = columnText(statement, 0) {
                        result[term] = Int(sqlite3_column_int64(statement, 1))
                    }
                }
            }
        }
        return result
    }

    private func populateQueryTerms(
        _ groups: [[String: FuzzyCandidate]],
        connection: OpaquePointer
    ) throws {
        try executeRequired(
            """
            CREATE TEMP TABLE IF NOT EXISTS query_terms(
                query_term_index INTEGER NOT NULL,
                candidate TEXT NOT NULL,
                edit_distance INTEGER NOT NULL,
                weighted_cost REAL NOT NULL,
                quality REAL NOT NULL,
                PRIMARY KEY(query_term_index, candidate)
            ) WITHOUT ROWID
            """,
            connection: connection,
            operation: "create query terms"
        )
        try executeRequired("DELETE FROM query_terms", connection: connection, operation: "clear query terms")
        try withStatement(
            "INSERT INTO query_terms(query_term_index, candidate, edit_distance, weighted_cost, quality) VALUES(?1, ?2, ?3, ?4, ?5)",
            connection: connection,
            operationName: "insert query term"
        ) { statement in
            for (index, group) in groups.enumerated() {
                for (candidate, match) in group {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    try bind(
                        .integer(Int64(index)), to: statement, index: 1, connection: connection,
                        operation: "bind term index")
                    try bind(
                        .text(candidate), to: statement, index: 2, connection: connection, operation: "bind candidate")
                    try bind(
                        .integer(Int64(match.editDistance)), to: statement, index: 3,
                        connection: connection,
                        operation: "bind distance")
                    try bind(
                        .double(match.weightedCost), to: statement, index: 4,
                        connection: connection, operation: "bind weighted cost")
                    try bind(
                        .double(match.quality), to: statement, index: 5,
                        connection: connection, operation: "bind correction quality")
                    try requireDone(sqlite3_step(statement), connection: connection, operation: "insert query term")
                }
            }
        }
    }

    private func uniformFuzzyMatch(
        groups: [[String: FuzzyCandidate]],
        queryTerms: [String]
    ) -> FuzzyDocumentMatch? {
        guard groups.count == queryTerms.count else { return nil }
        var evidence: [ClipboardSearchTermEvidence] = []
        evidence.reserveCapacity(groups.count)
        var totalEditDistance = 0
        var minimumQuality = 1.0
        for (index, group) in groups.enumerated() {
            guard group.count == 1, let (candidate, match) = group.first else { return nil }
            evidence.append(
                ClipboardSearchTermEvidence(
                    queryTermIndex: index,
                    normalizedQueryTerm: queryTerms[index],
                    normalizedMatchedTerm: candidate,
                    editDistance: match.editDistance,
                    weightedEditCost: match.weightedCost
                )
            )
            totalEditDistance += match.editDistance
            minimumQuality = min(minimumQuality, match.quality)
        }
        return FuzzyDocumentMatch(
            terms: evidence,
            totalEditDistance: totalEditDistance,
            correctionQuality: minimumQuality
        )
    }

    private func fuzzyDistances(
        termCount: Int,
        instanceTable: String,
        query: ClipboardQuery,
        connection: OpaquePointer
    ) throws -> [UUID: FuzzyDocumentMatch] {
        var values: [SQLiteValue] = [.integer(Int64(termCount))]
        let filter = filterSQL(query.filters, values: &values)
        let sql = """
            WITH ranked_candidates AS (
                SELECT wi.doc,
                       qt.query_term_index,
                       qt.candidate,
                       qt.edit_distance,
                       qt.weighted_cost,
                       qt.quality,
                       ROW_NUMBER() OVER (
                           PARTITION BY wi.doc, qt.query_term_index
                           ORDER BY qt.edit_distance ASC,
                                    qt.weighted_cost ASC,
                                    qt.quality DESC,
                                    qt.candidate ASC
                       ) AS candidate_rank
                FROM query_terms qt
                JOIN \(instanceTable) wi ON wi.term = qt.candidate
            ), resolved AS (
                SELECT doc, query_term_index, candidate, edit_distance, weighted_cost, quality
                FROM ranked_candidates
                WHERE candidate_rank = 1
            ), complete_documents AS (
                SELECT doc
                FROM resolved
                GROUP BY doc
                HAVING COUNT(*) = ?1
            )
            SELECT d.item_id,
                   resolved.query_term_index,
                   resolved.candidate,
                   resolved.edit_distance,
                   resolved.weighted_cost,
                   resolved.quality
            FROM complete_documents
            JOIN resolved ON resolved.doc = complete_documents.doc
            JOIN documents d ON d.rowid = complete_documents.doc
            JOIN search_metadata m ON m.document_id = d.rowid
            WHERE 1 = 1 \(filter)
              AND NOT EXISTS (
                  SELECT 1 FROM query_excluded_documents excluded
                  WHERE excluded.item_id = d.item_id
              )
            ORDER BY d.item_id, resolved.query_term_index
            """
        let queryTerms = ClipboardQueryPlan(query.text).normalizedTerms
        var resolvedByID: [UUID: [(term: ClipboardSearchTermEvidence, quality: Double)]] = [:]
        try withStatement(sql, connection: connection, operationName: "resolve fuzzy distances") { statement in
            try bind(values, to: statement, connection: connection, operation: "bind fuzzy filters")
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                try requireRow(code, connection: connection, operation: "resolve fuzzy distances")
                guard let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
                    let candidate = columnText(statement, 2)
                else { continue }
                let termIndex = Int(sqlite3_column_int64(statement, 1))
                guard queryTerms.indices.contains(termIndex) else { continue }
                let evidence = ClipboardSearchTermEvidence(
                    queryTermIndex: termIndex,
                    normalizedQueryTerm: queryTerms[termIndex],
                    normalizedMatchedTerm: candidate,
                    editDistance: Int(sqlite3_column_int64(statement, 3)),
                    weightedEditCost: sqlite3_column_double(statement, 4)
                )
                resolvedByID[id, default: []].append(
                    (term: evidence, quality: sqlite3_column_double(statement, 5))
                )
            }
        }
        return resolvedByID.compactMapValues { resolved in
            guard resolved.count == termCount else { return nil }
            let ordered = resolved.sorted { $0.term.queryTermIndex < $1.term.queryTermIndex }
            return FuzzyDocumentMatch(
                terms: ordered.map(\.term),
                totalEditDistance: ordered.reduce(0) { $0 + $1.term.editDistance },
                correctionQuality: ordered.map(\.quality).min() ?? 0
            )
        }
    }

    private func filterSQL(_ filters: ClipboardFilters, values: inout [SQLiteValue]) -> String {
        var clauses: [String] = []
        if filters.requiresBookmark { clauses.append("m.bookmarked = 1") }
        if let interval = filters.copiedAt {
            values.append(.double(interval.start.timeIntervalSince1970))
            clauses.append("m.copied_at >= ?\(values.count)")
            values.append(.double(interval.end.timeIntervalSince1970))
            clauses.append("m.copied_at < ?\(values.count)")
        }
        if !filters.sourceBundleIdentifiers.isEmpty {
            let normalized = filters.sourceBundleIdentifiers.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.sorted()
            let placeholders = normalized.map { value -> String in
                values.append(.text(value))
                return "?\(values.count)"
            }
            clauses.append("m.source_bundle IN (\(placeholders.joined(separator: ",")))")
        }
        if !filters.kinds.isEmpty {
            let placeholders = filters.kinds.map(\.rawValue).sorted().map { value -> String in
                values.append(.text(value))
                return "?\(values.count)"
            }
            clauses.append("m.kind IN (\(placeholders.joined(separator: ",")))")
        }
        return clauses.isEmpty ? "" : " AND " + clauses.joined(separator: " AND ")
    }

    private func merge(_ hit: ClipboardSearchHit, into results: inout [UUID: ClipboardSearchHit]) {
        if let current = results[hit.itemID], !hitPrecedes(hit, current) { return }
        results[hit.itemID] = hit
    }

    private func hitPrecedes(_ lhs: ClipboardSearchHit, _ rhs: ClipboardSearchHit) -> Bool {
        if lhs.region != rhs.region { return lhs.region == .strict }
        if lhs.region == .similar {
            let leftQuality = lhs.evidence.correctionQuality ?? 0
            let rightQuality = rhs.evidence.correctionQuality ?? 0
            if leftQuality != rightQuality { return leftQuality > rightQuality }
            if lhs.rank.editDistance != rhs.rank.editDistance {
                return lhs.rank.editDistance < rhs.rank.editDistance
            }
            if lhs.rank.fieldPriority != rhs.rank.fieldPriority {
                return lhs.rank.fieldPriority > rhs.rank.fieldPriority
            }
            if lhs.rank.relevance.score != rhs.rank.relevance.score {
                return lhs.rank.relevance.score < rhs.rank.relevance.score
            }
            if lhs.rank.copiedAt != rhs.rank.copiedAt {
                return lhs.rank.copiedAt > rhs.rank.copiedAt
            }
            return lhs.itemID.uuidString < rhs.itemID.uuidString
        }
        if lhs.rank.tier != rhs.rank.tier { return lhs.rank.tier > rhs.rank.tier }
        if lhs.rank.fieldPriority != rhs.rank.fieldPriority {
            return lhs.rank.fieldPriority > rhs.rank.fieldPriority
        }
        if lhs.rank.editDistance != rhs.rank.editDistance { return lhs.rank.editDistance < rhs.rank.editDistance }
        if lhs.rank.relevance.score != rhs.rank.relevance.score {
            return lhs.rank.relevance.score < rhs.rank.relevance.score
        }
        if lhs.rank.copiedAt != rhs.rank.copiedAt { return lhs.rank.copiedAt > rhs.rank.copiedAt }
        return lhs.itemID.uuidString < rhs.itemID.uuidString
    }

    private func upsert(
        _ document: ClipboardSearchPreparedDocument,
        knownState: ClipboardSearchStoredState?,
        connection: OpaquePointer
    ) throws {
        if knownState == nil {
            try execute(
                """
                INSERT INTO documents(
                    item_id, content_revision, source_revision, ocr_revision,
                    content, source, ocr, asset_state, asset_fingerprint,
                    content_length, source_length, ocr_length
                ) VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
                """,
                values: [
                    .text(document.item.id.uuidString),
                    .blob(document.revisions.content),
                    .blob(document.revisions.source),
                    .blob(document.revisions.ocr),
                    .text(document.content ?? ""),
                    .text(document.item.sourceAppDisplayName ?? ""),
                    .text(document.item.ocrText ?? ""),
                    .integer(Int64(document.assetState.rawValue)),
                    document.assetFingerprint.map(SQLiteValue.blob) ?? .null,
                    .integer(Int64(searchLength(document.content ?? ""))),
                    .integer(Int64(searchLength(document.item.sourceAppDisplayName ?? ""))),
                    .integer(Int64(searchLength(document.item.ocrText ?? ""))),
                ],
                connection: connection,
                operation: "insert document"
            )
            try insertMetadata(document.item, revision: document.revisions.metadata, connection: connection)
            return
        }

        if knownState?.contentRevision != document.revisions.content
            || knownState?.assetState == .pending
            || knownState?.assetState != document.assetState
            || knownState?.assetFingerprint != document.assetFingerprint
        {
            if let content = document.content {
                try execute(
                    """
                    UPDATE documents
                    SET content = ?2, content_revision = ?3, asset_state = ?4,
                        asset_fingerprint = ?5, content_length = ?6
                    WHERE item_id = ?1
                    """,
                    values: [
                        .text(document.item.id.uuidString), .text(content),
                        .blob(document.revisions.content), .integer(Int64(document.assetState.rawValue)),
                        document.assetFingerprint.map(SQLiteValue.blob) ?? .null,
                        .integer(Int64(searchLength(content))),
                    ],
                    connection: connection,
                    operation: "update content"
                )
            } else if document.assetState == .pending {
                try execute(
                    "UPDATE documents SET asset_state = ?2 WHERE item_id = ?1",
                    values: [.text(document.item.id.uuidString), .integer(Int64(document.assetState.rawValue))],
                    connection: connection,
                    operation: "mark pending asset"
                )
            }
        }
        if knownState?.sourceRevision != document.revisions.source {
            try execute(
                "UPDATE documents SET source = ?2, source_revision = ?3, source_length = ?4 WHERE item_id = ?1",
                values: [
                    .text(document.item.id.uuidString), .text(document.item.sourceAppDisplayName ?? ""),
                    .blob(document.revisions.source),
                    .integer(Int64(searchLength(document.item.sourceAppDisplayName ?? ""))),
                ],
                connection: connection,
                operation: "update source"
            )
        }
        if knownState?.ocrRevision != document.revisions.ocr {
            try execute(
                "UPDATE documents SET ocr = ?2, ocr_revision = ?3, ocr_length = ?4 WHERE item_id = ?1",
                values: [
                    .text(document.item.id.uuidString), .text(document.item.ocrText ?? ""),
                    .blob(document.revisions.ocr),
                    .integer(Int64(searchLength(document.item.ocrText ?? ""))),
                ],
                connection: connection,
                operation: "update OCR"
            )
        }
        if knownState?.metadataRevision != document.revisions.metadata {
            try updateMetadata(document.item, connection: connection)
        }
    }

    private func searchLength(_ text: String) -> Int {
        ClipboardSearchTextNormalizer.wordTerms(in: text).count
    }

    private func insertMetadata(
        _ item: ClipboardItem,
        revision: Data,
        connection: OpaquePointer
    ) throws {
        try execute(
            """
            INSERT INTO search_metadata(
                document_id, metadata_revision, kind, source_bundle, copied_at, bookmarked
            ) SELECT rowid, ?2, ?3, ?4, ?5, ?6 FROM documents WHERE item_id = ?1
            """,
            values: [
                .text(item.id.uuidString), .blob(revision), .text(item.kind.rawValue),
                .text(item.normalizedSourceAppBundleIdentifier ?? ""),
                .double(item.timestamp.timeIntervalSince1970), .integer(item.isBookmarked ? 1 : 0),
            ],
            connection: connection,
            operation: "insert metadata"
        )
    }

    private func updateMetadata(_ item: ClipboardItem, connection: OpaquePointer) throws {
        let revision = ClipboardSearchFieldRevisions.make(for: item).metadata
        try executeExpectingSingleChange(
            """
            UPDATE search_metadata SET
                metadata_revision = ?2, kind = ?3, source_bundle = ?4,
                copied_at = ?5, bookmarked = ?6
            WHERE document_id = (SELECT rowid FROM documents WHERE item_id = ?1)
            """,
            values: [
                .text(item.id.uuidString), .blob(revision), .text(item.kind.rawValue),
                .text(item.normalizedSourceAppBundleIdentifier ?? ""),
                .double(item.timestamp.timeIntervalSince1970), .integer(item.isBookmarked ? 1 : 0),
            ],
            connection: connection,
            operation: "update metadata"
        )
    }

    private func pendingAssetCount() throws -> Int {
        try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            return try withStatement(
                "SELECT pending_asset_count FROM search_control WHERE id = 1",
                connection: writer,
                operationName: "count pending assets"
            ) { statement in
                let code = sqlite3_step(statement)
                try requireRow(code, connection: writer, operation: "count pending assets")
                return Int(sqlite3_column_int64(statement, 0))
            }
        }
    }

    private func writeTransaction(
        checkCancellation: @escaping @Sendable () throws -> Void = { try Task.checkCancellation() },
        _ body: () throws -> Void
    ) throws {
        try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            let delays: [TimeInterval] = [0.025, 0.1, 0.4]
            var attempt = 0
            while true {
                do {
                    if let code = faultInjector.injectedCode(at: .begin) {
                        throw sqliteError(code: code, connection: writer, operation: "begin transaction")
                    }
                    try executeRequired("BEGIN IMMEDIATE", connection: writer, operation: "begin transaction")
                    var transactionCommitted = false
                    do {
                        try body()
                        var commitAttempt = 0
                        while true {
                            if let injected = faultInjector.injectedCode(at: .commitBeforeCall) {
                                let primaryCode = injected & 0xFF
                                if primaryCode == SQLITE_BUSY || primaryCode == SQLITE_LOCKED,
                                    commitAttempt < delays.count
                                {
                                    try retryClock.sleep(
                                        for: delays[commitAttempt],
                                        checkCancellation: checkCancellation
                                    )
                                    commitAttempt += 1
                                    continue
                                }
                                throw sqliteError(
                                    code: injected,
                                    connection: writer,
                                    operation: "commit transaction"
                                )
                            }
                            let commitCode = sqlite3_exec(writer, "COMMIT", nil, nil, nil)
                            if commitCode == SQLITE_OK {
                                transactionCommitted = true
                                if let injected = faultInjector.injectedCode(at: .commitAfterCall) {
                                    isInvalidated = true
                                    throw ClipboardSearchServiceError.connectionInvalidated(
                                        code: injected,
                                        operation: "publish committed transaction"
                                    )
                                }
                                break
                            }
                            let primaryCode = commitCode & 0xFF
                            if primaryCode == SQLITE_BUSY || primaryCode == SQLITE_LOCKED,
                                commitAttempt < delays.count
                            {
                                try retryClock.sleep(
                                    for: delays[commitAttempt],
                                    checkCancellation: checkCancellation
                                )
                                commitAttempt += 1
                                continue
                            }
                            isInvalidated = true
                            if primaryCode == SQLITE_CORRUPT || primaryCode == SQLITE_NOTADB {
                                throw ClipboardSearchServiceError.corrupt
                            }
                            throw ClipboardSearchServiceError.connectionInvalidated(
                                code: commitCode,
                                operation: "commit transaction"
                            )
                        }
                        if let injected = faultInjector.injectedCode(at: .publishPostCommit) {
                            isInvalidated = true
                            throw ClipboardSearchServiceError.connectionInvalidated(
                                code: injected,
                                operation: "publish post-commit state"
                            )
                        }
                        return
                    } catch {
                        if transactionCommitted { throw error }
                        if isInvalidated { throw error }
                        let rollbackCode =
                            faultInjector.injectedCode(at: .rollback)
                            ?? sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
                        if rollbackCode != SQLITE_OK {
                            isInvalidated = true
                            throw ClipboardSearchServiceError.connectionInvalidated(
                                code: rollbackCode,
                                operation: "rollback transaction"
                            )
                        }
                        throw error
                    }
                } catch let error as ClipboardSearchServiceError {
                    guard case .sqlite(let code, _, _) = error,
                        (code & 0xFF) == SQLITE_BUSY || (code & 0xFF) == SQLITE_LOCKED,
                        attempt < delays.count
                    else { throw error }
                    try retryClock.sleep(
                        for: delays[attempt],
                        checkCancellation: checkCancellation
                    )
                    attempt += 1
                }
            }
        }
    }

    private func createSchema() throws {
        guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
        try executeRequired("BEGIN IMMEDIATE", connection: writer, operation: "begin schema")
        do {
            let statements = [
                """
                CREATE TABLE documents(
                    rowid INTEGER PRIMARY KEY,
                    item_id TEXT NOT NULL UNIQUE,
                    content_revision BLOB NOT NULL,
                    source_revision BLOB NOT NULL,
                    ocr_revision BLOB NOT NULL,
                    content TEXT NOT NULL,
                    source TEXT NOT NULL,
                    ocr TEXT NOT NULL,
                    asset_state INTEGER NOT NULL DEFAULT 0,
                    asset_fingerprint BLOB,
                    content_length INTEGER NOT NULL DEFAULT 0,
                    source_length INTEGER NOT NULL DEFAULT 0,
                    ocr_length INTEGER NOT NULL DEFAULT 0
                )
                """,
                """
                CREATE TABLE search_metadata(
                    document_id INTEGER PRIMARY KEY REFERENCES documents(rowid) ON DELETE CASCADE,
                    metadata_revision BLOB NOT NULL,
                    kind TEXT NOT NULL,
                    source_bundle TEXT NOT NULL,
                    copied_at REAL NOT NULL,
                    bookmarked INTEGER NOT NULL
                )
                """,
                "CREATE INDEX metadata_bookmark_date ON search_metadata(bookmarked, copied_at DESC)",
                "CREATE INDEX metadata_bundle_date ON search_metadata(source_bundle, copied_at DESC)",
                "CREATE INDEX metadata_kind_date ON search_metadata(kind, copied_at DESC)",
                "CREATE INDEX metadata_date ON search_metadata(copied_at DESC)",
                "CREATE INDEX pending_assets ON documents(rowid) WHERE asset_state = 1",
                "CREATE VIRTUAL TABLE content_trigram USING fts5(content, content='documents', content_rowid='rowid', tokenize='trigram remove_diacritics 1')",
                // Word retrieval needs document/column postings, not every token
                // offset. `detail=column` prevents repeated words in multi-MiB
                // documents from turning a prefix query into millions of position
                // visits. Context positions remain available through the trigram
                // tables above.
                "CREATE VIRTUAL TABLE content_word USING fts5(content, content='documents', content_rowid='rowid', tokenize='unicode61 remove_diacritics 1', prefix='1 2 3', detail='column')",
                "CREATE VIRTUAL TABLE source_trigram USING fts5(source, content='documents', content_rowid='rowid', tokenize='trigram remove_diacritics 1')",
                "CREATE VIRTUAL TABLE source_word USING fts5(source, content='documents', content_rowid='rowid', tokenize='unicode61 remove_diacritics 1', prefix='1 2 3', detail='column')",
                "CREATE VIRTUAL TABLE ocr_trigram USING fts5(ocr, content='documents', content_rowid='rowid', tokenize='trigram remove_diacritics 1')",
                "CREATE VIRTUAL TABLE ocr_word USING fts5(ocr, content='documents', content_rowid='rowid', tokenize='unicode61 remove_diacritics 1', prefix='1 2 3', detail='column')",
                "CREATE VIRTUAL TABLE content_word_rows USING fts5vocab(content_word, 'row')",
                "CREATE VIRTUAL TABLE source_word_rows USING fts5vocab(source_word, 'row')",
                "CREATE VIRTUAL TABLE ocr_word_rows USING fts5vocab(ocr_word, 'row')",
                "CREATE VIRTUAL TABLE content_trigram_rows USING fts5vocab(content_trigram, 'row')",
                "CREATE VIRTUAL TABLE source_trigram_rows USING fts5vocab(source_trigram, 'row')",
                "CREATE VIRTUAL TABLE ocr_trigram_rows USING fts5vocab(ocr_trigram, 'row')",
                "CREATE VIRTUAL TABLE content_word_instances USING fts5vocab(content_word, 'instance')",
                "CREATE VIRTUAL TABLE source_word_instances USING fts5vocab(source_word, 'instance')",
                "CREATE VIRTUAL TABLE ocr_word_instances USING fts5vocab(ocr_word, 'instance')",
                """
                CREATE TABLE search_control(
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    clean_shutdown INTEGER NOT NULL,
                    last_integrity_check REAL,
                    history_revision INTEGER NOT NULL DEFAULT 0,
                    index_generation INTEGER NOT NULL DEFAULT 0,
                    vocabulary_generation INTEGER NOT NULL DEFAULT 0,
                    vocabulary_sequence INTEGER NOT NULL DEFAULT 0,
                    applied_vocabulary_sequence INTEGER NOT NULL DEFAULT 0,
                    active_vocabulary_build_id TEXT,
                    document_count INTEGER NOT NULL DEFAULT 0,
                    pending_asset_count INTEGER NOT NULL DEFAULT 0,
                    content_length_sum INTEGER NOT NULL DEFAULT 0,
                    source_length_sum INTEGER NOT NULL DEFAULT 0,
                    ocr_length_sum INTEGER NOT NULL DEFAULT 0
                    ,analyzer_version INTEGER NOT NULL DEFAULT \(ClipboardSearchSchema.analyzerVersion)
                    ,relevance_policy_version INTEGER NOT NULL DEFAULT \(ClipboardSearchSchema.relevancePolicyVersion)
                )
                """,
                """
                CREATE TABLE vocabulary_delta(
                    term TEXT PRIMARY KEY,
                    first_sequence INTEGER NOT NULL
                ) WITHOUT ROWID
                """,
                """
                CREATE TABLE vocabulary_build(
                    build_id TEXT PRIMARY KEY,
                    base_sequence INTEGER NOT NULL,
                    state INTEGER NOT NULL
                ) WITHOUT ROWID
                """,
                """
                CREATE TABLE vocabulary_node(
                    build_id TEXT NOT NULL,
                    node_index INTEGER NOT NULL,
                    term TEXT NOT NULL,
                    parent_index INTEGER,
                    edge_distance INTEGER,
                    document_frequency INTEGER NOT NULL,
                    PRIMARY KEY(build_id, node_index)
                ) WITHOUT ROWID
                """,
                "INSERT INTO search_control(id, clean_shutdown) VALUES(1, 0)",
            ]
            for statement in statements {
                try executeRequired(statement, connection: writer, operation: "create schema")
            }
            try createFTSTriggers(connection: writer)
            try createControlTriggers(connection: writer)
            try executeRequired(
                "PRAGMA user_version = \(ClipboardSearchSchema.currentVersion)",
                connection: writer,
                operation: "set schema version"
            )
            try executeRequired("COMMIT", connection: writer, operation: "commit schema")
        } catch {
            _ = sqlite3_exec(writer, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    private func createControlTriggers(connection: OpaquePointer) throws {
        try executeRequired(
            """
            CREATE TRIGGER documents_control_ai AFTER INSERT ON documents BEGIN
                UPDATE search_control SET
                    document_count = document_count + 1,
                    pending_asset_count = pending_asset_count + CASE WHEN new.asset_state = 1 THEN 1 ELSE 0 END,
                    content_length_sum = content_length_sum + new.content_length,
                    source_length_sum = source_length_sum + new.source_length,
                    ocr_length_sum = ocr_length_sum + new.ocr_length
                WHERE id = 1;
            END
            """,
            connection: connection,
            operation: "create document control insert trigger"
        )
        try executeRequired(
            """
            CREATE TRIGGER documents_control_ad AFTER DELETE ON documents BEGIN
                UPDATE search_control SET
                    document_count = document_count - 1,
                    pending_asset_count = pending_asset_count - CASE WHEN old.asset_state = 1 THEN 1 ELSE 0 END,
                    content_length_sum = content_length_sum - old.content_length,
                    source_length_sum = source_length_sum - old.source_length,
                    ocr_length_sum = ocr_length_sum - old.ocr_length
                WHERE id = 1;
            END
            """,
            connection: connection,
            operation: "create document control delete trigger"
        )
        try executeRequired(
            """
            CREATE TRIGGER documents_control_au
            AFTER UPDATE OF asset_state, content_length, source_length, ocr_length ON documents BEGIN
                UPDATE search_control SET
                    pending_asset_count = pending_asset_count
                        - CASE WHEN old.asset_state = 1 THEN 1 ELSE 0 END
                        + CASE WHEN new.asset_state = 1 THEN 1 ELSE 0 END,
                    content_length_sum = content_length_sum - old.content_length + new.content_length,
                    source_length_sum = source_length_sum - old.source_length + new.source_length,
                    ocr_length_sum = ocr_length_sum - old.ocr_length + new.ocr_length
                WHERE id = 1;
            END
            """,
            connection: connection,
            operation: "create document control update trigger"
        )
    }

    private func createFTSTriggers(connection: OpaquePointer) throws {
        let fields = ["content", "source", "ocr"]
        let insertBody = fields.flatMap { field in
            [
                "INSERT INTO \(field)_trigram(rowid, \(field)) VALUES(new.rowid, new.\(field));",
                "INSERT INTO \(field)_word(rowid, \(field)) VALUES(new.rowid, new.\(field));",
            ]
        }.joined(separator: " ")
        let deleteBody = fields.flatMap { field in
            [
                "INSERT INTO \(field)_trigram(\(field)_trigram, rowid, \(field)) VALUES('delete', old.rowid, old.\(field));",
                "INSERT INTO \(field)_word(\(field)_word, rowid, \(field)) VALUES('delete', old.rowid, old.\(field));",
            ]
        }.joined(separator: " ")
        try executeRequired(
            "CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN \(insertBody) END",
            connection: connection,
            operation: "create insert trigger"
        )
        try executeRequired(
            "CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN \(deleteBody) END",
            connection: connection,
            operation: "create delete trigger"
        )
        for field in fields {
            try executeRequired(
                """
                CREATE TRIGGER documents_\(field)_au
                AFTER UPDATE OF \(field) ON documents
                WHEN old.\(field) IS NOT new.\(field)
                BEGIN
                    INSERT INTO \(field)_trigram(\(field)_trigram, rowid, \(field))
                        VALUES('delete', old.rowid, old.\(field));
                    INSERT INTO \(field)_trigram(rowid, \(field)) VALUES(new.rowid, new.\(field));
                    INSERT INTO \(field)_word(\(field)_word, rowid, \(field))
                        VALUES('delete', old.rowid, old.\(field));
                    INSERT INTO \(field)_word(rowid, \(field)) VALUES(new.rowid, new.\(field));
                END
                """,
                connection: connection,
                operation: "create \(field) update trigger"
            )
        }
    }

    private func validateSchema() throws {
        guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
        let required = [
            "documents", "search_metadata", "content_trigram", "content_word",
            "source_trigram", "source_word", "ocr_trigram", "ocr_word",
            "content_word_rows", "source_word_rows", "ocr_word_rows",
            "content_trigram_rows", "source_trigram_rows", "ocr_trigram_rows",
            "content_word_instances", "source_word_instances", "ocr_word_instances",
            "search_control", "vocabulary_delta", "vocabulary_build",
            "vocabulary_node",
        ]
        let placeholders = required.indices.map { "?\($0 + 1)" }.joined(separator: ",")
        let count = try withStatement(
            "SELECT COUNT(*) FROM sqlite_master WHERE name IN (\(placeholders))",
            connection: writer,
            operationName: "validate schema"
        ) { statement in
            for (index, name) in required.enumerated() {
                try bind(
                    .text(name), to: statement, index: Int32(index + 1), connection: writer,
                    operation: "bind schema name")
            }
            let code = sqlite3_step(statement)
            try requireRow(code, connection: writer, operation: "validate schema")
            return Int(sqlite3_column_int(statement, 0))
        }
        guard count == required.count else { throw ClipboardSearchServiceError.corrupt }
        for table in ["content_word", "source_word", "ocr_word"] {
            let schema = try withStatement(
                "SELECT sql FROM sqlite_master WHERE name = ?1",
                connection: writer,
                operationName: "validate word index detail"
            ) { statement in
                try bind(
                    .text(table),
                    to: statement,
                    index: 1,
                    connection: writer,
                    operation: "bind word index name"
                )
                let code = sqlite3_step(statement)
                try requireRow(code, connection: writer, operation: "validate word index detail")
                return columnText(statement, 0) ?? ""
            }
            guard schema.lowercased().contains("detail='column'") else {
                throw ClipboardSearchServiceError.corrupt
            }
        }
    }

    private func validateControlVersions() throws {
        guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
        let versions = try withStatement(
            "SELECT analyzer_version, relevance_policy_version FROM search_control WHERE id = 1",
            connection: writer,
            operationName: "validate search policy versions"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: writer, operation: "validate search policy versions")
            return (
                analyzer: Int(sqlite3_column_int(statement, 0)),
                relevance: Int(sqlite3_column_int(statement, 1))
            )
        }
        guard versions.analyzer == ClipboardSearchSchema.analyzerVersion else {
            throw SearchDatabaseValidationError.analyzerMismatch(
                found: versions.analyzer,
                expected: ClipboardSearchSchema.analyzerVersion
            )
        }
        guard versions.relevance == ClipboardSearchSchema.relevancePolicyVersion else {
            throw SearchDatabaseValidationError.relevancePolicyMismatch(
                found: versions.relevance,
                expected: ClipboardSearchSchema.relevancePolicyVersion
            )
        }
    }

    private func prepareControlState() throws {
        guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
        let control = try withStatement(
            "SELECT clean_shutdown, last_integrity_check FROM search_control WHERE id = 1",
            connection: writer,
            operationName: "read shutdown state"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: writer, operation: "read shutdown state")
            return (
                clean: sqlite3_column_int(statement, 0) == 1,
                lastCheck: sqlite3_column_type(statement, 1) == SQLITE_NULL
                    ? nil : sqlite3_column_double(statement, 1)
            )
        }
        if !control.clean {
            try performIntegrityCheck(connection: writer)
        } else {
            let now = Date().timeIntervalSince1970
            let sevenDays = TimeInterval(7 * 24 * 60 * 60)
            requiresIdleIntegrityCheck =
                control.lastCheck == nil
                || control.lastCheck! > now
                || now - control.lastCheck! >= sevenDays
        }
        try executeRequired(
            "UPDATE search_control SET clean_shutdown = 0 WHERE id = 1",
            connection: writer,
            operation: "mark database open"
        )
    }

    func performIntegrityCheckIfDue() throws {
        try writerLock.withLock {
            guard requiresIdleIntegrityCheck else { return }
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            try performIntegrityCheck(connection: writer)
            requiresIdleIntegrityCheck = false
        }
    }

    private func performIntegrityCheck(connection: OpaquePointer) throws {
        let result = try withStatement(
            "PRAGMA quick_check",
            connection: connection,
            operationName: "integrity check"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "integrity check")
            return columnText(statement, 0)
        }
        guard result == "ok" else { throw ClipboardSearchServiceError.corrupt }
        try execute(
            "UPDATE search_control SET last_integrity_check = ?1 WHERE id = 1",
            values: [.double(Date().timeIntervalSince1970)],
            connection: connection,
            operation: "record integrity check"
        )
    }

    private func configure(_ connection: OpaquePointer?) throws {
        guard let connection else { throw ClipboardSearchServiceError.openDatabase("Missing connection") }
        for sql in [
            "PRAGMA journal_mode=WAL", "PRAGMA synchronous=NORMAL", "PRAGMA temp_store=MEMORY",
            "PRAGMA foreign_keys=ON", "PRAGMA busy_timeout=1000",
        ] {
            try executeRequired(sql, connection: connection, operation: "configure database")
        }
        try executeRequired(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.buffer_query_tokens
            USING fts5(text, tokenize='unicode61 remove_diacritics 1')
            """,
            connection: connection,
            operation: "create query tokenizer"
        )
        try executeRequired(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.buffer_query_token_instances
            USING fts5vocab(buffer_query_tokens, 'instance')
            """,
            connection: connection,
            operation: "create query tokenizer vocabulary"
        )
    }

    private func queryPlan(
        for query: String,
        connection: OpaquePointer
    ) throws -> ClipboardQueryPlan {
        try executeRequired(
            "DELETE FROM temp.buffer_query_tokens",
            connection: connection,
            operation: "clear query tokenizer"
        )
        try execute(
            "INSERT INTO temp.buffer_query_tokens(rowid, text) VALUES(1, ?1)",
            values: [.text(query)],
            connection: connection,
            operation: "tokenize search query"
        )
        let terms = try withStatement(
            """
            SELECT term
            FROM temp.buffer_query_token_instances
            WHERE doc = 1
            ORDER BY offset
            """,
            connection: connection,
            operationName: "read search query tokens"
        ) { statement in
            var values: [String] = []
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { return values }
                try requireRow(code, connection: connection, operation: "read search query tokens")
                if let term = columnText(statement, 0) { values.append(term) }
            }
        }
        return ClipboardQueryPlan(
            normalizedPhrase: ClipboardSearchTextNormalizer.normalize(query),
            normalizedTerms: terms
        )
    }

    private func validateControlCounters() throws {
        guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
        let totals = try withStatement(
            """
            SELECT COUNT(*),
                   COALESCE(SUM(CASE WHEN asset_state = 1 THEN 1 ELSE 0 END), 0),
                   COALESCE(SUM(content_length), 0),
                   COALESCE(SUM(source_length), 0),
                   COALESCE(SUM(ocr_length), 0)
            FROM documents
            """,
            connection: writer,
            operationName: "validate search counters"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: writer, operation: "validate search counters")
            return (0..<5).map { sqlite3_column_int64(statement, Int32($0)) }
        }
        try execute(
            """
            UPDATE search_control SET
                document_count = ?1,
                pending_asset_count = ?2,
                content_length_sum = ?3,
                source_length_sum = ?4,
                ocr_length_sum = ?5
            WHERE id = 1
            """,
            values: totals.map(SQLiteValue.integer),
            connection: writer,
            operation: "repair search counters"
        )
    }

    private func userVersion(_ connection: OpaquePointer?) throws -> Int {
        guard let connection else { throw ClipboardSearchServiceError.openDatabase("Missing connection") }
        return try withStatement(
            "PRAGMA user_version",
            connection: connection,
            operationName: "read schema version"
        ) { statement in
            let code = sqlite3_step(statement)
            try requireRow(code, connection: connection, operation: "read schema version")
            return Int(sqlite3_column_int(statement, 0))
        }
    }

    private enum SQLiteValue {
        case text(String)
        case blob(Data)
        case integer(Int64)
        case double(Double)
        case null
    }

    private func execute(
        _ sql: String,
        values: [SQLiteValue],
        connection: OpaquePointer,
        operation: String
    ) throws {
        try withStatement(sql, connection: connection, operationName: operation) { statement in
            try bind(values, to: statement, connection: connection, operation: operation)
            try requireDone(sqlite3_step(statement), connection: connection, operation: operation)
        }
    }

    private func executeExpectingSingleChange(
        _ sql: String,
        values: [SQLiteValue],
        connection: OpaquePointer,
        operation: String
    ) throws {
        try execute(sql, values: values, connection: connection, operation: operation)
        guard sqlite3_changes(connection) == 1 else {
            throw ClipboardSearchServiceError.indexDrift
        }
    }

    private func executeRequired(
        _ sql: String,
        connection: OpaquePointer,
        operation: String
    ) throws {
        let code = sqlite3_exec(connection, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw sqliteError(code: code, connection: connection, operation: operation) }
    }

    private func bestEffortClearTemporaryTable(
        _ table: TemporaryQueryTable,
        connection: OpaquePointer
    ) {
        let code = sqlite3_exec(connection, "DELETE FROM \(table.rawValue)", nil, nil, nil)
        guard code != SQLITE_OK else { return }
        BufferLogger.persistence.error(
            "SQLite cleanup failed for \(table.rawValue, privacy: .public), code \(code)"
        )
    }

    private func beginReadSnapshot(connection: OpaquePointer, operation: String) throws {
        if sqlite3_get_autocommit(connection) == 0 {
            rollbackReadSnapshot(connection: connection)
        }
        guard sqlite3_get_autocommit(connection) != 0 else {
            throw ClipboardSearchServiceError.connectionInvalidated(
                code: SQLITE_ABORT,
                operation: "recover stale read transaction"
            )
        }
        try executeRequired("BEGIN", connection: connection, operation: operation)
    }

    private func rollbackReadSnapshot(connection: OpaquePointer) {
        guard sqlite3_get_autocommit(connection) == 0 else { return }
        // sqlite3_interrupt may race with the first rollback attempt. Once the
        // operation that observed the interrupt has returned, a second attempt
        // reliably restores autocommit on this connection.
        for _ in 0..<3 {
            _ = sqlite3_exec(connection, "ROLLBACK", nil, nil, nil)
            if sqlite3_get_autocommit(connection) != 0 { return }
        }
    }

    private func withStatement<T>(
        _ sql: String,
        connection: OpaquePointer,
        operationName: String,
        _ body: (OpaquePointer) throws -> T
    ) throws -> T {
        diagnosticsLock.withLock { preparedStatementCount += 1 }
        if let code = faultInjector.injectedCode(
            at: .prepare(operation: SQLiteOperation(operationName))
        ) {
            throw ClipboardSearchServiceError.sqlite(
                code: code,
                operation: SQLiteOperation(operationName),
                message: "Injected SQLite failure"
            )
        }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw sqliteError(code: code, connection: connection, operation: operationName)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(
        _ values: [SQLiteValue],
        to statement: OpaquePointer,
        connection: OpaquePointer,
        operation: String
    ) throws {
        for (offset, value) in values.enumerated() {
            try bind(value, to: statement, index: Int32(offset + 1), connection: connection, operation: operation)
        }
    }

    private func bind(
        _ value: SQLiteValue,
        to statement: OpaquePointer,
        index: Int32,
        connection: OpaquePointer,
        operation: String
    ) throws {
        let code: Int32
        switch value {
        case .text(let value):
            code = sqlite3_bind_text(statement, index, value, -1, Self.transient)
        case .blob(let value):
            code = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
        case .integer(let value):
            code = sqlite3_bind_int64(statement, index, value)
        case .double(let value):
            code = sqlite3_bind_double(statement, index, value)
        case .null:
            code = sqlite3_bind_null(statement, index)
        }
        guard code == SQLITE_OK else { throw sqliteError(code: code, connection: connection, operation: operation) }
    }

    private func requireRow(_ code: Int32, connection: OpaquePointer, operation: String) throws {
        let resolvedCode =
            faultInjector.injectedCode(at: .step(operation: SQLiteOperation(operation))) ?? code
        guard resolvedCode == SQLITE_ROW else {
            throw sqliteError(code: resolvedCode, connection: connection, operation: operation)
        }
    }

    private func requireDone(_ code: Int32, connection: OpaquePointer, operation: String) throws {
        let resolvedCode =
            faultInjector.injectedCode(at: .step(operation: SQLiteOperation(operation))) ?? code
        guard resolvedCode == SQLITE_DONE else {
            throw sqliteError(code: resolvedCode, connection: connection, operation: operation)
        }
    }

    private func sqliteError(
        code: Int32,
        connection: OpaquePointer,
        operation: String
    ) -> Error {
        let primary = code & 0xFF
        if primary == SQLITE_INTERRUPT { return CancellationError() }
        if primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB { return ClipboardSearchServiceError.corrupt }
        return ClipboardSearchServiceError.sqlite(
            code: code,
            operation: SQLiteOperation(operation),
            message: String(cString: sqlite3_errmsg(connection))
        )
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private func columnData(_ statement: OpaquePointer, _ index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func quotedFTS(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func insertPersistentTerms(
        _ terms: [String],
        buildID: String,
        frequencies: [String: Int] = [:],
        into tree: inout ClipboardPersistentFuzzyVocabulary,
        connection: OpaquePointer
    ) throws {
        for term in terms.sorted() {
            guard let insertion = tree.insert(term) else { continue }
            try execute(
                """
                INSERT INTO vocabulary_node(
                    build_id, node_index, term, parent_index, edge_distance, document_frequency
                ) VALUES(?1, ?2, ?3, ?4, ?5, ?6)
                """,
                values: [
                    .text(buildID),
                    .integer(Int64(insertion.nodeIndex)),
                    .text(term),
                    insertion.parentDatabaseID.map(SQLiteValue.integer) ?? .null,
                    insertion.parentDatabaseID == nil
                        ? .null : .integer(Int64(insertion.edgeDistance)),
                    .integer(Int64(frequencies[term, default: 0])),
                ],
                connection: connection,
                operation: "insert fuzzy term"
            )
            tree.assignDatabaseID(Int64(insertion.nodeIndex), toNodeAt: insertion.nodeIndex)
        }
    }

    private func fuzzyTerms(in fields: [String]) -> [String] {
        var result = Set<String>()
        for field in fields {
            for term in ClipboardSearchTextNormalizer.wordTerms(in: field) {
                if term.count >= 3, term.count <= 64, !term.allSatisfy(\.isNumber) {
                    result.insert(term)
                }
            }
        }
        return Array(result)
    }

    private func compactVocabularyIfNeeded() throws {
        let token = ClipboardSearchCancellationToken()
        let activeCount = try maintenanceReaderLock.withLock {
            guard let maintenanceReader else {
                throw ClipboardSearchServiceError.openDatabase("Missing maintenance reader")
            }
            return try activeVocabularyTerms(
                connection: maintenanceReader,
                cancellationToken: token
            ).count
        }
        let persistedCount = try writerLock.withLock {
            guard let writer else { throw ClipboardSearchServiceError.openDatabase("Missing writer") }
            return try withStatement(
                """
                SELECT COUNT(*) FROM vocabulary_node
                WHERE build_id = (
                    SELECT active_vocabulary_build_id FROM search_control WHERE id = 1
                )
                """,
                connection: writer,
                operationName: "count persisted vocabulary"
            ) { statement in
                let code = sqlite3_step(statement)
                try requireRow(code, connection: writer, operation: "count persisted vocabulary")
                return Int(sqlite3_column_int64(statement, 0))
            }
        }
        guard persistedCount >= 10_000,
            persistedCount > Int(Double(max(1, activeCount)) * 1.25),
            persistedCount - activeCount >= 10_000
        else { return }
        try prewarmVocabulary()
    }

    private func scheduleVocabularyCompaction() {
        let shouldSchedule = vocabularyLock.withLock { () -> Bool in
            guard !isVocabularyCompactionScheduled else { return false }
            isVocabularyCompactionScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        BlockingDatabaseExecutor.task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try self.compactVocabularyIfNeeded()
            } catch {
                self.vocabularyLock.withLock {
                    self.successfulVocabularyMutations = max(
                        self.successfulVocabularyMutations,
                        500
                    )
                }
            }
            self.vocabularyLock.withLock {
                self.isVocabularyCompactionScheduled = false
            }
        }
    }

    private func makeSnippet(
        text: String,
        phrase: String?,
        terms: [String],
        sessionID: ClipboardSearchSessionID,
        field: ClipboardMatchField
    ) -> ClipboardSearchSnippet? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var bestRange: Range<String.Index>?
        if let phrase, !phrase.isEmpty {
            bestRange = text.range(of: phrase, options: options)
        }
        if bestRange == nil {
            for term in terms where !term.isEmpty {
                guard let range = text.range(of: term, options: options) else { continue }
                if bestRange == nil || range.lowerBound < bestRange!.lowerBound { bestRange = range }
            }
        }
        guard let bestRange else { return nil }

        let lower = text.distance(from: text.startIndex, to: bestRange.lowerBound)
        let upper = text.distance(from: text.startIndex, to: bestRange.upperBound)
        let characterCount = text.count
        let leadingEllipsis = lower > 0
        let trailingEllipsis = upper < characterCount
        let ellipsisBudget = (leadingEllipsis ? 1 : 0) + (trailingEllipsis ? 1 : 0)
        let contentBudget = max(1, 120 - ellipsisBudget)
        let highlightedLength = max(1, upper - lower)
        let spare = max(0, contentBudget - min(highlightedLength, contentBudget))
        var start = max(0, lower - spare / 2)
        var end = min(characterCount, start + contentBudget)
        if end - start < contentBudget { start = max(0, end - contentBudget) }
        if upper > end {
            end = min(characterCount, upper)
            start = max(0, end - contentBudget)
        }
        if lower < start { start = lower }

        let visibleHighlightStart = max(start, lower)
        let visibleHighlightEnd = min(end, max(visibleHighlightStart + 1, upper))
        let startIndex = text.index(text.startIndex, offsetBy: start)
        let highlightStartIndex = text.index(text.startIndex, offsetBy: visibleHighlightStart)
        let highlightEndIndex = text.index(text.startIndex, offsetBy: visibleHighlightEnd)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        var segments: [ClipboardSearchSnippetSegment] = []
        if start > 0 { segments.append(.init(text: "…", isHighlighted: false)) }
        if start < visibleHighlightStart {
            segments.append(
                .init(text: String(text[startIndex..<highlightStartIndex]), isHighlighted: false)
            )
        }
        segments.append(
            .init(
                text: String(text[highlightStartIndex..<highlightEndIndex]),
                isHighlighted: true
            )
        )
        if visibleHighlightEnd < end {
            segments.append(
                .init(text: String(text[highlightEndIndex..<endIndex]), isHighlighted: false)
            )
        }
        if end < characterCount { segments.append(.init(text: "…", isHighlighted: false)) }
        return ClipboardSearchSnippet(
            sessionID: sessionID,
            field: field,
            segments: segments
        )
    }

    private func secureFiles() throws {
        let fileManager = FileManager.default
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try Self.excludeFromBackup(url)
        }
    }

    private static func open(
        at url: URL,
        createIfNeeded: Bool,
        faultInjector: any ClipboardSQLiteFaultInjecting
    ) throws -> OpaquePointer {
        if let code = faultInjector.injectedCode(at: .open) {
            throw ClipboardSearchServiceError.sqlite(
                code: code,
                operation: "open database",
                message: "Injected SQLite failure"
            )
        }
        var connection: OpaquePointer?
        let flags =
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            | (createIfNeeded ? SQLITE_OPEN_CREATE : 0)
        let code = sqlite3_open_v2(
            url.path,
            &connection,
            flags,
            nil
        )
        guard code == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open search database"
            if let connection { sqlite3_close(connection) }
            throw ClipboardSearchServiceError.sqlite(code: code, operation: "open database", message: message)
        }
        return connection
    }

    private static func excludeFromBackup(_ directory: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(values)
    }
}
