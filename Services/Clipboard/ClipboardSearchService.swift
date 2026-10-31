import Foundation
import SQLite3
import os

enum ClipboardSearchTextNormalizer {
    private static let invariantLocale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: invariantLocale
        )
    }

    static func wordTerms(in text: String) -> [String] {
        normalize(text).split { character in
            !character.isLetter && !character.isNumber
        }.map(String.init)
    }
}

struct ClipboardQueryPlan: Equatable, Sendable {
    let normalizedPhrase: String
    let normalizedTerms: [String]

    init(_ query: String) {
        normalizedPhrase = ClipboardSearchTextNormalizer.normalize(query)
        normalizedTerms = ClipboardSearchTextNormalizer.wordTerms(in: query)
    }

    init(normalizedPhrase: String, normalizedTerms: [String]) {
        self.normalizedPhrase = normalizedPhrase
        self.normalizedTerms = normalizedTerms
    }

    var allowsFuzzyMatching: Bool {
        !normalizedTerms.isEmpty
            && normalizedTerms.count <= 8
            && normalizedPhrase.count <= 256
            && !normalizedPhrase.contains(where: { "_./:@#-$\\".contains($0) })
            && normalizedTerms.contains(where: ClipboardFuzzyPolicyV2.isPotentiallyFuzzy)
    }

    var prefersLiteralPhrase: Bool {
        normalizedTerms.count > 1
            || normalizedPhrase.contains(where: { !$0.isLetter && !$0.isNumber })
    }
}

enum ClipboardFuzzyPolicyV2 {
    static let maximumCandidatesPerTerm = 32
    static let maximumCandidatesPerQuery = 128
    static let maximumStrictResultsBeforeSkippingSimilar = 8

    static func isPotentiallyFuzzy(_ term: String) -> Bool {
        let characters = Array(term)
        guard characters.count >= 3, characters.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return characters.allSatisfy(isSupportedFuzzyCharacter(_:))
    }

    static func isTechnicalToken(_ term: String) -> Bool {
        if UUID(uuidString: term) != nil { return true }
        if term.allSatisfy(\.isNumber) { return true }
        if term.contains(where: { "_./:@#-$\\".contains($0) }) { return true }
        let hasLetter = term.contains(where: \.isLetter)
        let hasNumber = term.contains(where: \.isNumber)
        if hasLetter && hasNumber { return true }
        if term.count >= 7, term.allSatisfy({ $0.isHexDigit }) { return true }
        return false
    }

    static func maximumEditDistance(for term: String, field: ClipboardMatchField) -> Int {
        guard isPotentiallyFuzzy(term), !isTechnicalToken(term) else { return 0 }
        switch term.count {
        case ...7:
            return 1
        default:
            return 2
        }
    }

    static func accepts(
        query: String,
        candidate: String,
        field: ClipboardMatchField,
        documentFrequency: Int,
        eligibleDocumentCount: Int
    ) -> (quality: Double, weightedCost: Double)? {
        guard isPotentiallyFuzzy(query), !isTechnicalToken(query) else { return nil }
        let rawDistance = ClipboardTextMatcher.damerauLevenshteinDistance(query, candidate)
        let maximumDistance = maximumEditDistance(for: query, field: field)
        guard rawDistance > 0, rawDistance <= maximumDistance else { return nil }

        if query.count == 3 {
            guard isSingleAdjacentTransposition(query, candidate) else { return nil }
        } else if query.count == 4 {
            guard !isSingleSubstitution(query, candidate) else { return nil }
        } else if rawDistance == 1, isSingleSubstitution(query, candidate) {
            let requiredPrefixLength = query.count == 5 ? 2 : 1
            guard commonPrefixLength(query, candidate) >= requiredPrefixLength else { return nil }
        }

        let weightedCost = weightedEditCost(query, candidate, field: field)
        let maximumLength = max(query.count, candidate.count)
        guard maximumLength > 0 else { return nil }
        let similarity = 1 - weightedCost / Double(maximumLength)
        let prefixBonus = 0.03 * Double(min(commonPrefixLength(query, candidate), 2))
        // A term occurring in a single document is evidence, not breadth. Penalize
        // only the frequency above that baseline so tiny histories do not suppress
        // high-confidence transpositions such as `gti` -> `git`.
        let excessBreadth = max(0, log1p(Double(max(0, documentFrequency))) - log(2))
        let breadthPenalty =
            0.18 * excessBreadth
            / log1p(Double(max(2, eligibleDocumentCount)))
        let quality = min(1, max(0, similarity + prefixBonus - breadthPenalty))
        let threshold: Double
        switch field {
        case .content: threshold = 0.80
        case .ocr: threshold = 0.74
        case .sourceApplication: threshold = 0.84
        }
        return quality >= threshold ? (quality, weightedCost) : nil
    }

    static func isSingleAdjacentTransposition(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard left.count == right.count, left.count >= 2 else { return false }
        let mismatches = left.indices.filter { left[$0] != right[$0] }
        guard mismatches.count == 2,
            mismatches[1] == mismatches[0] + 1
        else { return false }
        return left[mismatches[0]] == right[mismatches[1]]
            && left[mismatches[1]] == right[mismatches[0]]
    }

    static func isSingleSubstitution(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard left.count == right.count else { return false }
        return zip(left, right).lazy.filter(!=).count == 1
    }

    static func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix(while: ==).count
    }

    private static func isSupportedFuzzyCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (0x0041...0x024F).contains(value)
        }
    }

    private static func weightedEditCost(
        _ lhs: String,
        _ rhs: String,
        field: ClipboardMatchField
    ) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return Double(right.count) * 0.75 }
        guard !right.isEmpty else { return Double(left.count) * 0.75 }

        var matrix = Array(
            repeating: Array(repeating: 0.0, count: right.count + 1),
            count: left.count + 1
        )
        for index in 0...left.count { matrix[index][0] = Double(index) * 0.75 }
        for index in 0...right.count { matrix[0][index] = Double(index) * 0.75 }

        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                let substitutionCost = substitutionCost(
                    left[leftIndex - 1],
                    right[rightIndex - 1],
                    field: field
                )
                var cost = min(
                    matrix[leftIndex - 1][rightIndex] + 0.75,
                    matrix[leftIndex][rightIndex - 1] + 0.75,
                    matrix[leftIndex - 1][rightIndex - 1] + substitutionCost
                )
                if leftIndex > 1,
                    rightIndex > 1,
                    left[leftIndex - 1] == right[rightIndex - 2],
                    left[leftIndex - 2] == right[rightIndex - 1]
                {
                    cost = min(cost, matrix[leftIndex - 2][rightIndex - 2] + 0.45)
                }
                matrix[leftIndex][rightIndex] = cost
            }
        }
        return matrix[left.count][right.count]
    }

    private static func substitutionCost(
        _ lhs: Character,
        _ rhs: Character,
        field: ClipboardMatchField
    ) -> Double {
        guard lhs != rhs else { return 0 }
        guard field == .ocr else { return 1 }
        let pair = String([lhs, rhs]).lowercased()
        let reverse = String([rhs, lhs]).lowercased()
        let commonOCRPairs: Set<String> = ["0o", "1l", "1i"]
        return commonOCRPairs.contains(pair) || commonOCRPairs.contains(reverse) ? 0.45 : 1
    }
}

struct ClipboardIndexedToken: Equatable, Sendable {
    let normalizedText: String
    let range: Range<String.Index>
}

enum ClipboardTextMatcher {
    struct FuzzyMatch: Sendable {
        let ranges: [Range<String.Index>]
        let totalEditDistance: Int
    }

    static func tokens(in text: String) -> [ClipboardIndexedToken] {
        var result: [ClipboardIndexedToken] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            let normalizedText = ClipboardSearchTextNormalizer.normalize(String(text[range]))
            guard !normalizedText.isEmpty else { return }
            result.append(ClipboardIndexedToken(normalizedText: normalizedText, range: range))
        }
        return result
    }

    static func exactRanges(in text: String, normalizedPhrase: String) -> [Range<String.Index>] {
        guard !normalizedPhrase.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var remainingRange = text.startIndex..<text.endIndex
        while let range = text.range(
            of: normalizedPhrase,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: remainingRange
        ) {
            ranges.append(range)
            guard range.upperBound < text.endIndex else { break }
            remainingRange = range.upperBound..<text.endIndex
        }
        return ranges
    }

    static func fuzzyMatch(
        tokens: [ClipboardIndexedToken],
        resolvedTerms: [[String: Int]]
    ) -> FuzzyMatch? {
        guard !resolvedTerms.isEmpty else { return nil }

        var ranges: [Range<String.Index>] = []
        var totalEditDistance = 0
        var tokenIndex = 0

        for candidates in resolvedTerms {
            var matchedToken: ClipboardIndexedToken?
            var matchedDistance = 0
            while tokenIndex < tokens.count {
                let token = tokens[tokenIndex]
                tokenIndex += 1
                if let distance = candidates[token.normalizedText] {
                    matchedToken = token
                    matchedDistance = distance
                    break
                }
            }

            guard let matchedToken else { return nil }
            ranges.append(matchedToken.range)
            totalEditDistance += matchedDistance
        }

        return FuzzyMatch(ranges: ranges, totalEditDistance: totalEditDistance)
    }

    static func highlightedRanges(
        in text: String,
        queryPlan: ClipboardQueryPlan,
        classification: ClipboardMatchClassification
    ) -> [Range<String.Index>] {
        switch classification {
        case .exact:
            return exactRanges(in: text, normalizedPhrase: queryPlan.normalizedPhrase)
        case .fuzzy:
            let indexedTokens = tokens(in: text)
            let resolvedTerms = queryPlan.normalizedTerms.map { term in
                var candidates: [String: Int] = [:]
                for token in indexedTokens {
                    guard
                        let distance = acceptedEditDistance(
                            from: term,
                            to: token.normalizedText
                        )
                    else { continue }
                    candidates[token.normalizedText] = distance
                }
                return candidates
            }
            return fuzzyMatch(tokens: indexedTokens, resolvedTerms: resolvedTerms)?.ranges ?? []
        }
    }

    static func acceptedEditDistance(from queryTerm: String, to candidate: String) -> Int? {
        if queryTerm.count < 3 || queryTerm.allSatisfy(\.isNumber) {
            return queryTerm == candidate ? 0 : nil
        }

        let maximumDistance = maximumEditDistance(forTermLength: queryTerm.count)
        guard abs(queryTerm.count - candidate.count) <= maximumDistance else { return nil }
        let distance = damerauLevenshteinDistance(queryTerm, candidate)
        return distance <= maximumDistance ? distance : nil
    }

    static func maximumEditDistance(forTermLength length: Int) -> Int {
        switch length {
        case ..<3: return 0
        case 3...7: return 1
        default: return 2
        }
    }

    static func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        let maximumDistance = left.count + right.count
        var matrix = Array(
            repeating: Array(repeating: 0, count: right.count + 2),
            count: left.count + 2
        )
        matrix[0][0] = maximumDistance
        for leftIndex in 0...left.count {
            matrix[leftIndex + 1][0] = maximumDistance
            matrix[leftIndex + 1][1] = leftIndex
        }
        for rightIndex in 0...right.count {
            matrix[0][rightIndex + 1] = maximumDistance
            matrix[1][rightIndex + 1] = rightIndex
        }

        var lastRowByCharacter: [Character: Int] = [:]
        for leftIndex in 1...left.count {
            var lastMatchingColumn = 0
            for rightIndex in 1...right.count {
                let transpositionRow = lastRowByCharacter[right[rightIndex - 1]] ?? 0
                let transpositionColumn = lastMatchingColumn
                var substitutionCost = 1
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    substitutionCost = 0
                    lastMatchingColumn = rightIndex
                }

                matrix[leftIndex + 1][rightIndex + 1] = min(
                    matrix[leftIndex][rightIndex] + substitutionCost,
                    matrix[leftIndex + 1][rightIndex] + 1,
                    matrix[leftIndex][rightIndex + 1] + 1,
                    matrix[transpositionRow][transpositionColumn]
                        + (leftIndex - transpositionRow - 1)
                        + 1
                        + (rightIndex - transpositionColumn - 1)
                )
            }
            lastRowByCharacter[left[leftIndex - 1]] = leftIndex
        }
        return matrix[left.count + 1][right.count + 1]
    }
}

// MARK: - Persistent search service

enum ClipboardSearchSchema {
    static let currentVersion = 6
    static let analyzerVersion = 1
    static let relevancePolicyVersion = 2
}

enum SearchDatabaseOpenMode: Equatable {
    case openExisting
    case createEmpty
}

enum SearchDatabaseValidationError: Error, Equatable {
    case schemaMismatch(found: Int, expected: Int)
    case analyzerMismatch(found: Int, expected: Int)
    case relevancePolicyMismatch(found: Int, expected: Int)
}

enum ClipboardSearchFailureKind: Equatable, Sendable {
    case storageFull
    case io
    case permission
    case unavailable
}

struct ClipboardSearchFailure: Equatable, Sendable {
    let kind: ClipboardSearchFailureKind
    let retryScheduled: Bool
}

enum ClipboardSearchPhase: Equatable, Sendable {
    case opening
    case indexing
    case ready
    case recovering
    case degraded(ClipboardSearchFailure)
}

enum ClipboardFuzzyPhase: Equatable, Sendable {
    case cold
    case loading
    case ready(generation: UInt64)
    case paused(ClipboardSearchFailure)
}

struct ClipboardSearchStatus: Equatable, Sendable {
    static let initial = ClipboardSearchStatus(
        indexGeneration: 0,
        indexedItemCount: 0,
        totalItemCount: 0,
        pendingAssetCount: 0,
        phase: .opening,
        fuzzyPhase: .cold
    )

    let indexGeneration: UInt64
    let indexedItemCount: Int
    let totalItemCount: Int
    let pendingAssetCount: Int
    let phase: ClipboardSearchPhase
    let fuzzyPhase: ClipboardFuzzyPhase

    init(
        indexGeneration: UInt64,
        indexedItemCount: Int,
        totalItemCount: Int,
        pendingAssetCount: Int,
        phase: ClipboardSearchPhase,
        fuzzyPhase: ClipboardFuzzyPhase = .cold
    ) {
        self.indexGeneration = indexGeneration
        self.indexedItemCount = indexedItemCount
        self.totalItemCount = totalItemCount
        self.pendingAssetCount = pendingAssetCount
        self.phase = phase
        self.fuzzyPhase = fuzzyPhase
    }

    var isReady: Bool { phase == .ready }
    var generation: UInt64 { indexGeneration }
}

enum ClipboardSearchChange: Sendable {
    case insert(ClipboardItem)
    case updateContent(ClipboardItem)
    case updateOCR(itemID: UUID, text: String?)
    case updateSource(itemID: UUID, displayName: String)
    case remove(UUID)
    case updateMetadata(ClipboardItem)
    case reset
}

struct ClipboardSearchChangeSet: Sendable {
    static let none = ClipboardSearchChangeSet(historyRevision: 0, changes: [])

    let historyRevision: UInt64
    let changes: [ClipboardSearchChange]

    init(historyRevision: UInt64 = 0, changes: [ClipboardSearchChange]) {
        self.historyRevision = historyRevision
        self.changes = changes
    }

    var isEmpty: Bool { changes.isEmpty }
}

struct ClipboardSearchReconcileContext: Sendable {
    let snapshot: [ClipboardItem]
    let historyRevision: UInt64
    let assetAccess: any ClipboardSearchAssetAccessing
}

struct SQLiteOperation: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    var description: String { rawValue }
}

enum ClipboardSearchServiceError: LocalizedError, Sendable {
    case openDatabase(String)
    case sqlite(code: Int32, operation: SQLiteOperation, message: String)
    case connectionInvalidated(code: Int32, operation: SQLiteOperation)
    case corrupt
    case interrupted
    case staleGeneration
    case indexDrift
    case execute(String)

    var errorDescription: String? {
        switch self {
        case .openDatabase(let message):
            message
        case .sqlite(_, let operation, let message):
            "\(operation): \(message)"
        case .connectionInvalidated(_, let operation):
            "\(operation): the database connection must be reopened"
        case .corrupt:
            "The search database is corrupt"
        case .interrupted:
            "The search was interrupted"
        case .staleGeneration:
            "The search generation is stale"
        case .indexDrift:
            "The search index no longer matches history"
        case .execute(let message):
            message
        }
    }
}

final class ClipboardSearchCancellationToken: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(uncheckedState: false)

    @discardableResult
    func cancel() -> Bool {
        state.withLockUnchecked { state in
            guard !state else { return false }
            state = true
            return true
        }
    }

    var isCancelled: Bool {
        state.withLockUnchecked { $0 }
    }

    func checkCancellation() throws {
        if isCancelled { throw CancellationError() }
    }
}

let clipboardSearchProgressCallback: @convention(c) (UnsafeMutableRawPointer?) -> Int32 =
    { context in
        guard let context else { return 0 }
        let token = Unmanaged<ClipboardSearchCancellationToken>
            .fromOpaque(context)
            .takeUnretainedValue()
        return token.isCancelled ? 1 : 0
    }

private final class ClipboardSearchDatabaseHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var database: ClipboardSearchDatabase?
    private var activeToken: ClipboardSearchCancellationToken?

    func install(_ database: ClipboardSearchDatabase) {
        lock.withLock { self.database = database }
    }

    func currentDatabase() -> ClipboardSearchDatabase? {
        lock.withLock { database }
    }

    func beginSearch(token: ClipboardSearchCancellationToken) {
        let interruptedDatabase = lock.withLock { () -> ClipboardSearchDatabase? in
            let shouldInterrupt = activeToken?.cancel() == true
            activeToken = token
            return shouldInterrupt ? database : nil
        }
        interruptedDatabase?.interruptSearch()
    }

    func endSearch(token: ClipboardSearchCancellationToken) {
        lock.withLock {
            if activeToken === token { activeToken = nil }
        }
    }

    func cancelCurrentSearch() {
        let database = lock.withLock { () -> ClipboardSearchDatabase? in
            guard activeToken?.cancel() == true else { return nil }
            return database
        }
        database?.interruptSearch()
    }

    @discardableResult
    func replaceDatabase(_ replacement: ClipboardSearchDatabase?) -> ClipboardSearchDatabase? {
        cancelCurrentSearch()
        return lock.withLock {
            let previous = database
            database = replacement
            return previous
        }
    }
}

/// The single boundary for synchronous SQLite and filesystem work that must not
/// occupy an actor executor. Keeping detached tasks here makes ownership and
/// priority propagation explicit at every call site.
enum BlockingDatabaseExecutor {
    @discardableResult
    static func task<Output: Sendable>(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () -> Output
    ) -> Task<Output, Never> {
        Task.detached(priority: priority, operation: operation)
    }

    @discardableResult
    static func task<Output: Sendable>(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () throws -> Output
    ) -> Task<Output, Error> {
        Task.detached(priority: priority, operation: operation)
    }

    static func run<Output: Sendable>(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () throws -> Output
    ) async throws -> Output {
        try await task(priority: priority, operation: operation).value
    }
}

private actor ClipboardSearchLatestWinsLane<Output: Sendable> {
    typealias Operation = @Sendable (ClipboardSearchCancellationToken) async throws -> Output

    private struct Work: Sendable {
        let id: UUID
        let token: ClipboardSearchCancellationToken
        let priority: TaskPriority
        let interrupt: @Sendable () -> Void
        let operation: Operation
        let continuation: CheckedContinuation<Output, Error>
    }

    private var active: Work?
    private var pending: Work?
    private var drainContinuations: [CheckedContinuation<Void, Never>] = []

    func submit(
        priority: TaskPriority = .userInitiated,
        interrupt: @escaping @Sendable () -> Void,
        operation: @escaping Operation
    ) async throws -> Output {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let work = Work(
                    id: id,
                    token: ClipboardSearchCancellationToken(),
                    priority: priority,
                    interrupt: interrupt,
                    operation: operation,
                    continuation: continuation
                )
                enqueue(work)
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func cancelAll() {
        if let pending {
            self.pending = nil
            pending.token.cancel()
            pending.continuation.resume(throwing: CancellationError())
        }
        if active?.token.cancel() == true { active?.interrupt() }
    }

    func cancelAndDrain() async {
        cancelAll()
        guard active != nil else { return }
        await withCheckedContinuation { continuation in
            drainContinuations.append(continuation)
        }
    }

    private func enqueue(_ work: Work) {
        if let pending {
            pending.token.cancel()
            pending.continuation.resume(throwing: CancellationError())
        }
        pending = work
        if let active {
            if active.token.cancel() { active.interrupt() }
        } else {
            startNext()
        }
    }

    private func cancel(id: UUID) {
        if pending?.id == id, let pending {
            self.pending = nil
            pending.token.cancel()
            pending.continuation.resume(throwing: CancellationError())
        }
        if active?.id == id {
            if active?.token.cancel() == true { active?.interrupt() }
        }
    }

    private func startNext() {
        guard active == nil, let work = pending else { return }
        pending = nil
        active = work
        Task(priority: work.priority) {
            let result: Result<Output, Error>
            do {
                result = .success(try await work.operation(work.token))
            } catch {
                result = .failure(error)
            }
            self.finish(id: work.id, result: result)
        }
    }

    private func finish(id: UUID, result: Result<Output, Error>) {
        guard let active, active.id == id else { return }
        self.active = nil
        active.continuation.resume(with: result)
        if pending == nil, !drainContinuations.isEmpty {
            let continuations = drainContinuations
            drainContinuations.removeAll()
            for continuation in continuations { continuation.resume() }
        }
        startNext()
    }
}

protocol ClipboardSearchServing: Sendable {
    func reconcile(
        snapshot: [ClipboardItem],
        historyRevision: UInt64,
        assetAccess: any ClipboardSearchAssetAccessing
    ) async -> ClipboardSearchStatus

    func apply(
        _ changeSet: ClipboardSearchChangeSet,
        currentSnapshot: [ClipboardItem],
        assetAccess: any ClipboardSearchAssetAccessing
    ) async -> ClipboardSearchStatus

    func search(_ request: ClipboardSearchRequest) async throws -> ClipboardSearchResponse
    func snippets(_ request: ClipboardSearchSnippetRequest) async throws
        -> ClipboardSearchSnippetBatch
    func searchableText(for itemID: UUID) async -> String?
    func statusUpdates() async -> AsyncStream<ClipboardSearchStatus>
    nonisolated func cancelActiveSearch()
}

actor ClipboardSearchService: ClipboardSearchServing {
    private enum SearchManifestError: Error {
        case malformed
        case incompatibleSchema(found: Int)
        case unsafeFilename
        case missingIndex
    }

    private struct ActiveIndexManifest: Codable, Sendable {
        let schemaVersion: Int
        let fileName: String
    }

    private struct SearchIndexFilename {
        let rawValue: String

        init?(_ rawValue: String) {
            guard rawValue == URL(fileURLWithPath: rawValue).lastPathComponent,
                !rawValue.contains("/"),
                !rawValue.contains("\\")
            else { return nil }
            if rawValue != "index-bootstrap.sqlite" {
                guard rawValue.hasPrefix("index-"), rawValue.hasSuffix(".sqlite") else {
                    return nil
                }
                let generation = rawValue.dropFirst("index-".count).dropLast(".sqlite".count)
                guard generation.count == 8,
                    generation.utf8.allSatisfy({ (48...57).contains($0) })
                else { return nil }
            }
            self.rawValue = rawValue
        }
    }

    private let databaseURL: URL
    private nonisolated let databaseHandle = ClipboardSearchDatabaseHandle()
    private var databaseLoadTask: Task<ClipboardSearchDatabase, Error>?
    private(set) var status = ClipboardSearchStatus.initial
    private var statusContinuations: [UUID: AsyncStream<ClipboardSearchStatus>.Continuation] = [:]
    private var indexedHistoryRevision: UInt64 = 0
    private var needsFullReconcile = false
    private var pendingAssetRetryTask: Task<Void, Never>?
    private var isSwitchingDatabase = false
    private var databaseRetryTask: Task<Void, Never>?
    private var databaseRetryAttempt = 0
    private var vocabularyWarmupTask: Task<Void, Never>?
    private var integrityCheckTask: Task<Void, Never>?
    private var activeDatabaseURL: URL?
    private var latestReconcileContext: ClipboardSearchReconcileContext?
    private let searchLane = ClipboardSearchLatestWinsLane<ClipboardSearchResponse>()
    private let snippetLane = ClipboardSearchLatestWinsLane<ClipboardSearchSnippetBatch>()
    private let maintenanceLane = ClipboardSearchLatestWinsLane<ClipboardSearchStatus>()
    private struct SearchSessionRecord: Sendable {
        let sessionID: ClipboardSearchSessionID
        let queryGeneration: UInt64
        let committedState: ClipboardSearchCommittedState
        var hitsByItemID: [UUID: ClipboardSearchHit]
    }

    private var activeSearchSessionID: ClipboardSearchSessionID?
    private var currentSearchSession: SearchSessionRecord?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    nonisolated func cancelActiveSearch() {
        databaseHandle.cancelCurrentSearch()
    }

    private func executeSearchPhase(
        request: ClipboardSearchRequest,
        sessionID: ClipboardSearchSessionID,
        phase: ClipboardSearchDatabase.SearchPhase,
        excluding excludedIDs: Set<UUID>
    ) async throws -> ClipboardSearchResponse {
        guard !isSwitchingDatabase else { throw CancellationError() }
        let database = try await resolvedDatabase()
        let servicePhase = status.phase
        return try await searchLane.submit(
            interrupt: { database.interruptSearch() },
            operation: { [databaseHandle] token in
                databaseHandle.beginSearch(token: token)
                defer { databaseHandle.endSearch(token: token) }
                let snapshot = try database.search(
                    query: request.query,
                    cancellationToken: token,
                    includeFuzzy: phase == .similar,
                    sessionID: sessionID,
                    phase: phase,
                    excluding: excludedIDs
                )
                try token.checkCancellation()
                guard snapshot.state.historyRevision == request.historyRevision else {
                    throw ClipboardSearchServiceError.staleGeneration
                }
                return ClipboardSearchResponse(
                    session: ClipboardSearchSession(
                        id: sessionID,
                        queryGeneration: request.queryGeneration,
                        committedState: snapshot.state
                    ),
                    coverage: ClipboardSearchCoverage(
                        corpusIsComplete: servicePhase == .ready,
                        similarResultsAreComplete: phase != .similar || servicePhase == .ready
                    ),
                    hits: snapshot.hits
                )
            }
        )
    }

    private func ensureActiveSession(
        _ sessionID: ClipboardSearchSessionID,
        request: ClipboardSearchRequest,
        state: ClipboardSearchCommittedState
    ) throws {
        guard activeSearchSessionID == sessionID,
            state.historyRevision == request.historyRevision
        else { throw ClipboardSearchServiceError.staleGeneration }
        if let currentSearchSession,
            currentSearchSession.sessionID == sessionID,
            currentSearchSession.committedState != state
        {
            throw ClipboardSearchServiceError.staleGeneration
        }
    }

    nonisolated func interruptSearch() {
        cancelActiveSearch()
    }

    func statusUpdates() -> AsyncStream<ClipboardSearchStatus> {
        let subscriberID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: ClipboardSearchStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        statusContinuations[subscriberID] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusContinuation(subscriberID) }
        }
        return stream
    }

    @discardableResult
    func reconcile(
        snapshot items: [ClipboardItem],
        historyRevision: UInt64,
        assetAccess: any ClipboardSearchAssetAccessing
    ) async -> ClipboardSearchStatus {
        latestReconcileContext = ClipboardSearchReconcileContext(
            snapshot: items,
            historyRevision: historyRevision,
            assetAccess: assetAccess
        )
        do {
            return try await maintenanceLane.submit(
                priority: .utility,
                interrupt: { [databaseHandle] in
                    databaseHandle.currentDatabase()?.interruptMaintenance()
                },
                operation: { [weak self] token in
                    guard let self else { throw CancellationError() }
                    return await self.performReconcile(
                        snapshot: items,
                        historyRevision: historyRevision,
                        assetAccess: assetAccess,
                        cancellationToken: token
                    )
                }
            )
        } catch {
            return status
        }
    }

    private func performReconcile(
        snapshot items: [ClipboardItem],
        historyRevision: UInt64,
        assetAccess: any ClipboardSearchAssetAccessing,
        cancellationToken: ClipboardSearchCancellationToken
    ) async -> ClipboardSearchStatus {
        do {
            try cancellationToken.checkCancellation()
        } catch {
            return status
        }
        if needsFullReconcile {
            return await rebuildShadowIndex(
                snapshot: items,
                historyRevision: historyRevision,
                assetAccess: assetAccess
            )
        }
        updateStatus(
            ClipboardSearchStatus(
                indexGeneration: status.indexGeneration,
                indexedItemCount: 0,
                totalItemCount: items.count,
                pendingAssetCount: status.pendingAssetCount,
                phase: .indexing,
                fuzzyPhase: status.fuzzyPhase
            ))

        let orderedItems = items.sorted { $0.timestamp > $1.timestamp }
        do {
            let database = try await resolvedDatabase()
            let indexedStates = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.indexedStates()
            }.value
            let initialCommittedState = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.committedState()
            }.value
            if initialCommittedState.historyRevision != historyRevision {
                try await BlockingDatabaseExecutor.task(priority: .utility) {
                    try database.beginIndexing(historyRevision: historyRevision)
                }.value
            }
            let currentIDs = Set(orderedItems.map(\.id))
            let staleIDs = Set(indexedStates.keys).subtracting(currentIDs)
            if !staleIDs.isEmpty {
                try await BlockingDatabaseExecutor.task(priority: .utility) {
                    try database.remove(itemIDs: staleIDs)
                }.value
            }

            let batches = Self.indexBatches(items: orderedItems)
            var indexedCount = 0
            var pendingAssetCount = 0
            var lastProgressPublication = ContinuousClock().now
            for batch in batches {
                try cancellationToken.checkCancellation()
                pendingAssetCount = try await BlockingDatabaseExecutor.task(priority: .utility) {
                    try database.reconcile(
                        items: batch,
                        knownStates: indexedStates,
                        assetAccess: assetAccess,
                        cancellationToken: cancellationToken
                    )
                }.value
                try cancellationToken.checkCancellation()
                indexedCount += batch.count
                let now = ContinuousClock().now
                let isFinal = indexedCount == orderedItems.count
                if isFinal || now - lastProgressPublication >= .milliseconds(250) {
                    updateStatus(
                        ClipboardSearchStatus(
                            indexGeneration: status.indexGeneration,
                            indexedItemCount: indexedCount,
                            totalItemCount: orderedItems.count,
                            pendingAssetCount: pendingAssetCount,
                            phase: .indexing,
                            fuzzyPhase: status.fuzzyPhase
                        ))
                    lastProgressPublication = now
                }
                await Task.yield()
            }

            try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.recordIndexedHistoryRevision(historyRevision)
            }.value
            let committedState = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.committedState()
            }.value
            indexedHistoryRevision = historyRevision
            needsFullReconcile = false
            databaseRetryTask?.cancel()
            databaseRetryTask = nil
            databaseRetryAttempt = 0
            updateStatus(
                ClipboardSearchStatus(
                    indexGeneration: committedState.indexGeneration,
                    indexedItemCount: orderedItems.count,
                    totalItemCount: orderedItems.count,
                    pendingAssetCount: pendingAssetCount,
                    phase: .ready,
                    fuzzyPhase: database.isVocabularyLoaded
                        ? .ready(generation: committedState.vocabularyGeneration) : .cold
                ))
            schedulePendingAssetRetries(
                historyRevision: historyRevision
            )
            scheduleIntegrityCheck(database: database)
        } catch is CancellationError {
            return status
        } catch is SearchDatabaseValidationError {
            needsFullReconcile = true
            return await rebuildShadowIndex(
                snapshot: items,
                historyRevision: historyRevision,
                assetAccess: assetAccess
            )
        } catch is SearchManifestError {
            needsFullReconcile = true
            return await rebuildShadowIndex(
                snapshot: items,
                historyRevision: historyRevision,
                assetAccess: assetAccess
            )
        } catch ClipboardSearchServiceError.corrupt {
            needsFullReconcile = true
            return await rebuildShadowIndex(
                snapshot: items,
                historyRevision: historyRevision,
                assetAccess: assetAccess
            )
        } catch {
            needsFullReconcile = true
            await handleDatabaseError(error, totalItemCount: items.count)
        }
        return status
    }

    @discardableResult
    func apply(
        _ changeSet: ClipboardSearchChangeSet,
        currentSnapshot: [ClipboardItem],
        assetAccess: any ClipboardSearchAssetAccessing
    ) async -> ClipboardSearchStatus {
        latestReconcileContext = ClipboardSearchReconcileContext(
            snapshot: currentSnapshot,
            historyRevision: changeSet.historyRevision,
            assetAccess: assetAccess
        )
        do {
            return try await maintenanceLane.submit(
                priority: .utility,
                interrupt: { [databaseHandle] in
                    databaseHandle.currentDatabase()?.interruptMaintenance()
                },
                operation: { [weak self] token in
                    guard let self else { throw CancellationError() }
                    return await self.performApply(
                        changeSet,
                        currentSnapshot: currentSnapshot,
                        assetAccess: assetAccess,
                        cancellationToken: token
                    )
                }
            )
        } catch {
            return status
        }
    }

    private func performApply(
        _ changeSet: ClipboardSearchChangeSet,
        currentSnapshot: [ClipboardItem],
        assetAccess: any ClipboardSearchAssetAccessing,
        cancellationToken: ClipboardSearchCancellationToken
    ) async -> ClipboardSearchStatus {
        if needsFullReconcile {
            return await performReconcile(
                snapshot: currentSnapshot,
                historyRevision: changeSet.historyRevision,
                assetAccess: assetAccess,
                cancellationToken: cancellationToken
            )
        }
        guard !changeSet.isEmpty else { return status }
        do {
            try cancellationToken.checkCancellation()
        } catch {
            return status
        }
        if let database = try? await resolvedDatabase(),
            let committed = try? database.committedState(),
            changeSet.historyRevision > committed.historyRevision &+ 1
        {
            needsFullReconcile = true
            return await performReconcile(
                snapshot: currentSnapshot,
                historyRevision: changeSet.historyRevision,
                assetAccess: assetAccess,
                cancellationToken: cancellationToken
            )
        }
        updateStatus(
            ClipboardSearchStatus(
                indexGeneration: status.indexGeneration,
                indexedItemCount: min(status.indexedItemCount, currentSnapshot.count),
                totalItemCount: currentSnapshot.count,
                pendingAssetCount: status.pendingAssetCount,
                phase: .indexing,
                fuzzyPhase: status.fuzzyPhase
            ))

        do {
            let database = try await resolvedDatabase()
            let pendingAssetCount = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.apply(
                    changeSet.changes,
                    currentSnapshot: currentSnapshot,
                    historyRevision: changeSet.historyRevision,
                    assetAccess: assetAccess,
                    cancellationToken: cancellationToken
                )
            }.value
            try cancellationToken.checkCancellation()
            let committedState = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try database.committedState()
            }.value
            indexedHistoryRevision = changeSet.historyRevision
            databaseRetryTask?.cancel()
            databaseRetryTask = nil
            databaseRetryAttempt = 0
            updateStatus(
                ClipboardSearchStatus(
                    indexGeneration: committedState.indexGeneration,
                    indexedItemCount: currentSnapshot.count,
                    totalItemCount: currentSnapshot.count,
                    pendingAssetCount: pendingAssetCount,
                    phase: .ready,
                    fuzzyPhase: database.isVocabularyLoaded
                        ? .ready(generation: committedState.vocabularyGeneration) : .cold
                ))
            pendingAssetRetryTask?.cancel()
            pendingAssetRetryTask = nil
            schedulePendingAssetRetries(
                historyRevision: changeSet.historyRevision
            )
        } catch is CancellationError {
            return status
        } catch {
            if Self.requiresFullReconcile(after: error) {
                needsFullReconcile = true
            }
            await handleDatabaseError(error, totalItemCount: currentSnapshot.count)
        }
        return status
    }

    func search(_ request: ClipboardSearchRequest) async throws -> ClipboardSearchResponse {
        guard !isSwitchingDatabase else { throw CancellationError() }
        guard !request.query.normalizedText.isEmpty else {
            let committedState =
                (try? await resolvedDatabase().committedState())
                ?? ClipboardSearchCommittedState(
                    indexGeneration: status.indexGeneration,
                    historyRevision: indexedHistoryRevision,
                    vocabularyGeneration: 0,
                    appliedVocabularySequence: 0
                )
            return ClipboardSearchResponse(
                session: ClipboardSearchSession(
                    id: ClipboardSearchSessionID(),
                    queryGeneration: request.queryGeneration,
                    committedState: committedState
                ),
                coverage: ClipboardSearchCoverage(
                    corpusIsComplete: status.isReady,
                    similarResultsAreComplete: true
                ),
                hits: []
            )
        }
        let sessionID = ClipboardSearchSessionID()
        activeSearchSessionID = sessionID
        databaseHandle.cancelCurrentSearch()
        let database = try await resolvedDatabase()
        if let integrityCheckTask {
            integrityCheckTask.cancel()
            self.integrityCheckTask = nil
            database.interruptMaintenance()
        }
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            let strict = try await executeSearchPhase(
                request: request,
                sessionID: sessionID,
                phase: .strict,
                excluding: []
            )
            try ensureActiveSession(
                sessionID,
                request: request,
                state: strict.session.committedState
            )

            var orderedHits = strict.hits
            var excludedItemIDs = Set(orderedHits.map(\.itemID))
            let substring = try await executeSearchPhase(
                request: request,
                sessionID: sessionID,
                phase: .substring,
                excluding: excludedItemIDs
            )
            try ensureActiveSession(
                sessionID,
                request: request,
                state: substring.session.committedState
            )
            orderedHits.append(contentsOf: substring.hits)
            excludedItemIDs.formUnion(substring.hits.map(\.itemID))

            let plan = ClipboardQueryPlan(request.query.text)
            let hasResolvedStrictTerm = strict.hits.contains { hit in
                switch hit.evidence.kind {
                case .literalPhrase, .exactToken, .prefix: return true
                case .substring, .fuzzyCorrection: return false
                }
            }
            var fuzzyIsComplete = true
            if strict.hits.count
                < ClipboardFuzzyPolicyV2.maximumStrictResultsBeforeSkippingSimilar,
                plan.allowsFuzzyMatching,
                !hasResolvedStrictTerm
            {
                scheduleVocabularyWarmup(database: database)
                let warmupTask = vocabularyWarmupTask
                let fuzzyDelay = Duration.milliseconds(140)
                let elapsed = startedAt.duration(to: clock.now)
                if elapsed < fuzzyDelay {
                    try await Task.sleep(for: fuzzyDelay - elapsed)
                }
                if let warmupTask { await warmupTask.value }
                try ensureActiveSession(
                    sessionID,
                    request: request,
                    state: substring.session.committedState
                )
                if case .ready = status.fuzzyPhase {
                    do {
                        let similar = try await executeSearchPhase(
                            request: request,
                            sessionID: sessionID,
                            phase: .similar,
                            excluding: excludedItemIDs
                        )
                        try ensureActiveSession(
                            sessionID,
                            request: request,
                            state: similar.session.committedState
                        )
                        orderedHits.append(contentsOf: similar.hits)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        fuzzyIsComplete = false
                        BufferLogger.persistence.error(
                            "Similar-result phase failed: \(String(describing: error), privacy: .public)"
                        )
                    }
                } else {
                    fuzzyIsComplete = false
                }
            }

            let response = ClipboardSearchResponse(
                session: ClipboardSearchSession(
                    id: sessionID,
                    queryGeneration: request.queryGeneration,
                    committedState: substring.session.committedState
                ),
                coverage: ClipboardSearchCoverage(
                    corpusIsComplete: status.phase == .ready,
                    similarResultsAreComplete: fuzzyIsComplete
                ),
                hits: orderedHits
            )
            currentSearchSession = SearchSessionRecord(
                sessionID: sessionID,
                queryGeneration: request.queryGeneration,
                committedState: response.session.committedState,
                hitsByItemID: Dictionary(
                    uniqueKeysWithValues: response.hits.map { ($0.itemID, $0) }
                )
            )
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch ClipboardSearchServiceError.staleGeneration {
            throw CancellationError()
        } catch {
            await handleDatabaseError(error, totalItemCount: status.totalItemCount)
            throw error
        }
    }

    func searchableText(for itemID: UUID) async -> String? {
        guard let database = try? await resolvedDatabase() else { return nil }
        return try? await BlockingDatabaseExecutor.task(priority: .utility) {
            try database.searchableText(for: itemID)
        }.value
    }

    func snippets(_ request: ClipboardSearchSnippetRequest) async throws -> ClipboardSearchSnippetBatch {
        guard !isSwitchingDatabase else { throw CancellationError() }
        let database = try await resolvedDatabase()
        let resolvedHits: [ClipboardSearchHit]
        guard let session = currentSearchSession,
            session.sessionID == request.session.id,
            session.queryGeneration == request.session.queryGeneration,
            session.committedState == request.session.committedState
        else { throw ClipboardSearchServiceError.staleGeneration }
        resolvedHits = request.itemIDs.compactMap { session.hitsByItemID[$0] }
        guard resolvedHits.count == request.itemIDs.count else {
            throw ClipboardSearchServiceError.staleGeneration
        }
        return try await snippetLane.submit(
            interrupt: { database.interruptSnippets() },
            operation: { token in
                let snapshot = try database.snippets(for: resolvedHits, cancellationToken: token)
                try token.checkCancellation()
                let state = snapshot.state
                guard state == request.session.committedState
                else { throw ClipboardSearchServiceError.staleGeneration }
                return ClipboardSearchSnippetBatch(
                    session: request.session,
                    snippetsByItemID: snapshot.snippets
                )
            }
        )
    }

    private func updateStatus(_ nextStatus: ClipboardSearchStatus) {
        status = nextStatus
        for continuation in statusContinuations.values {
            continuation.yield(nextStatus)
        }
    }

    private func removeStatusContinuation(_ subscriberID: UUID) {
        statusContinuations.removeValue(forKey: subscriberID)
    }

    private func resolvedDatabase() async throws -> ClipboardSearchDatabase {
        if let database = databaseHandle.currentDatabase() {
            return database
        }
        if let databaseLoadTask {
            do {
                let database = try await databaseLoadTask.value
                databaseHandle.install(database)
                self.databaseLoadTask = nil
                return database
            } catch {
                self.databaseLoadTask = nil
                throw error
            }
        }

        let databaseURL = try resolveActiveDatabaseURL()
        let openMode: SearchDatabaseOpenMode =
            FileManager.default.fileExists(
                atPath: databaseURL.path
            ) ? .openExisting : .createEmpty
        let task = BlockingDatabaseExecutor.task(priority: .utility) {
            try ClipboardSearchDatabase(databaseURL: databaseURL, openMode: openMode)
        }
        databaseLoadTask = task
        do {
            let database = try await task.value
            databaseHandle.install(database)
            activeDatabaseURL = databaseURL
            try persistActiveManifest(databaseURL: databaseURL)
            databaseLoadTask = nil
            return database
        } catch {
            databaseLoadTask = nil
            throw error
        }
    }

    private var manifestURL: URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("active-index.json")
    }

    private func resolveActiveDatabaseURL() throws -> URL {
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let data = try Data(contentsOf: manifestURL)
            let manifest: ActiveIndexManifest
            do {
                manifest = try JSONDecoder().decode(ActiveIndexManifest.self, from: data)
            } catch {
                throw SearchManifestError.malformed
            }
            guard manifest.schemaVersion == ClipboardSearchSchema.currentVersion else {
                throw SearchManifestError.incompatibleSchema(found: manifest.schemaVersion)
            }
            guard let fileName = SearchIndexFilename(manifest.fileName) else {
                throw SearchManifestError.unsafeFilename
            }
            let candidate = databaseURL.deletingLastPathComponent().appendingPathComponent(
                fileName.rawValue
            )
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                throw SearchManifestError.missingIndex
            }
            return candidate
        }
        if FileManager.default.fileExists(atPath: databaseURL.path) { return databaseURL }
        return databaseURL.deletingLastPathComponent().appendingPathComponent(
            "index-bootstrap.sqlite"
        )
    }

    private func persistActiveManifest(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let fileName = SearchIndexFilename(databaseURL.lastPathComponent) else {
            throw ClipboardSearchServiceError.openDatabase("Unsafe search index filename")
        }
        let manifest = ActiveIndexManifest(
            schemaVersion: ClipboardSearchSchema.currentVersion,
            fileName: fileName.rawValue
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = manifestURL
        try url.setResourceValues(values)
    }

    private func handleDatabaseError(_ error: Error, totalItemCount: Int) async {
        let hasRetry = latestReconcileContext != nil
        if hasRetry { scheduleDatabaseRetry() }
        let phase: ClipboardSearchPhase
        if case ClipboardSearchServiceError.corrupt = error {
            phase = .recovering
            databaseHandle.replaceDatabase(nil)
        } else if case ClipboardSearchServiceError.connectionInvalidated = error {
            phase = .degraded(
                ClipboardSearchFailure(
                    kind: Self.failureKind(for: error),
                    retryScheduled: hasRetry
                )
            )
            databaseHandle.replaceDatabase(nil)
        } else {
            phase = .degraded(
                ClipboardSearchFailure(
                    kind: Self.failureKind(for: error),
                    retryScheduled: hasRetry
                )
            )
        }
        updateStatus(
            ClipboardSearchStatus(
                indexGeneration: status.indexGeneration,
                indexedItemCount: status.indexedItemCount,
                totalItemCount: totalItemCount,
                pendingAssetCount: status.pendingAssetCount,
                phase: phase,
                fuzzyPhase: status.fuzzyPhase
            ))
    }

    private func scheduleDatabaseRetry() {
        guard databaseRetryTask == nil, latestReconcileContext != nil else { return }
        let delays: [Duration] = [.seconds(1), .seconds(5), .seconds(30), .seconds(300)]
        let delay = delays[min(databaseRetryAttempt, delays.count - 1)]
        databaseRetryAttempt += 1
        databaseRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await self?.performScheduledDatabaseRetry()
        }
    }

    private func performScheduledDatabaseRetry() async {
        databaseRetryTask = nil
        guard let context = latestReconcileContext else { return }
        _ = await reconcile(
            snapshot: context.snapshot,
            historyRevision: context.historyRevision,
            assetAccess: context.assetAccess
        )
        if status.isReady {
            databaseRetryAttempt = 0
        }
    }

    private func scheduleVocabularyWarmup(database: ClipboardSearchDatabase) {
        if database.isVocabularyLoaded {
            return
        }
        guard vocabularyWarmupTask == nil else { return }
        updateStatus(
            ClipboardSearchStatus(
                indexGeneration: status.indexGeneration,
                indexedItemCount: status.indexedItemCount,
                totalItemCount: status.totalItemCount,
                pendingAssetCount: status.pendingAssetCount,
                phase: status.phase,
                fuzzyPhase: .loading
            ))
        vocabularyWarmupTask = Task { [weak self] in
            let result = await BlockingDatabaseExecutor.task(priority: .utility) {
                Result { try database.prewarmVocabulary() }
            }.value
            await self?.finishVocabularyWarmup(result, database: database)
        }
    }

    private func finishVocabularyWarmup(
        _ result: Result<Void, Error>,
        database: ClipboardSearchDatabase
    ) async {
        vocabularyWarmupTask = nil
        guard databaseHandle.currentDatabase() === database else {
            // Recovery may have switched generations while the detached build
            // finished. An old tree must never alter the active status.
            return
        }
        switch result {
        case .success:
            let committed = try? database.committedState()
            updateStatus(
                ClipboardSearchStatus(
                    indexGeneration: committed?.indexGeneration ?? status.indexGeneration,
                    indexedItemCount: status.indexedItemCount,
                    totalItemCount: status.totalItemCount,
                    pendingAssetCount: status.pendingAssetCount,
                    phase: status.phase,
                    fuzzyPhase: .ready(generation: committed?.vocabularyGeneration ?? 0)
                ))
        case .failure(let error):
            if error is CancellationError { return }
            let failure = ClipboardSearchFailure(
                kind: Self.failureKind(for: error),
                retryScheduled: latestReconcileContext != nil
            )
            updateStatus(
                ClipboardSearchStatus(
                    indexGeneration: status.indexGeneration,
                    indexedItemCount: status.indexedItemCount,
                    totalItemCount: status.totalItemCount,
                    pendingAssetCount: status.pendingAssetCount,
                    phase: status.phase,
                    fuzzyPhase: .paused(failure)
                ))
        }
    }

    private func scheduleIntegrityCheck(database: ClipboardSearchDatabase) {
        guard integrityCheckTask == nil else { return }
        integrityCheckTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                try await BlockingDatabaseExecutor.task(priority: .background) {
                    try database.performIntegrityCheckIfDue()
                }.value
            } catch is CancellationError {
                // Interactive work will schedule another idle opportunity.
            } catch {
                await self?.handleDatabaseError(error, totalItemCount: await self?.status.totalItemCount ?? 0)
            }
            await self?.finishIntegrityCheck()
        }
    }

    private func finishIntegrityCheck() {
        integrityCheckTask = nil
    }

    private static func failureKind(for error: Error) -> ClipboardSearchFailureKind {
        let code: Int32
        switch error {
        case ClipboardSearchServiceError.sqlite(let value, _, _):
            code = value
        case ClipboardSearchServiceError.connectionInvalidated(let value, _):
            code = value
        default:
            return .unavailable
        }
        switch code & 0xFF {
        case SQLITE_FULL: return .storageFull
        case SQLITE_READONLY, SQLITE_PERM, SQLITE_CANTOPEN: return .permission
        case SQLITE_IOERR: return .io
        default: return .unavailable
        }
    }

    private static func requiresFullReconcile(after error: Error) -> Bool {
        if error is SearchDatabaseValidationError || error is SearchManifestError {
            return true
        }
        switch error {
        case ClipboardSearchServiceError.corrupt,
            ClipboardSearchServiceError.indexDrift,
            ClipboardSearchServiceError.connectionInvalidated:
            return true
        default:
            return false
        }
    }

    private func rebuildShadowIndex(
        snapshot: [ClipboardItem],
        historyRevision: UInt64,
        assetAccess: any ClipboardSearchAssetAccessing
    ) async -> ClipboardSearchStatus {
        let targetGeneration = status.indexGeneration &+ 1
        updateStatus(
            ClipboardSearchStatus(
                indexGeneration: status.indexGeneration,
                indexedItemCount: 0,
                totalItemCount: snapshot.count,
                pendingAssetCount: status.pendingAssetCount,
                phase: .recovering,
                fuzzyPhase: .cold
            ))
        let shadowURL = databaseURL.deletingLastPathComponent().appendingPathComponent(
            String(format: "index-%08llu.sqlite", targetGeneration)
        )
        do {
            if shadowURL != activeDatabaseURL {
                Self.removeInactiveIndexFiles(at: shadowURL)
            }
            let shadow = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try ClipboardSearchDatabase(databaseURL: shadowURL, openMode: .createEmpty)
            }.value
            try await BlockingDatabaseExecutor.task(priority: .utility) {
                try shadow.prepareIndexGeneration(targetGeneration)
            }.value
            let ordered = snapshot.sorted { $0.timestamp > $1.timestamp }
            var indexedCount = 0
            var pendingCount = 0
            for batch in Self.indexBatches(items: ordered) {
                try Task.checkCancellation()
                pendingCount = try await BlockingDatabaseExecutor.task(priority: .utility) {
                    try shadow.reconcile(
                        items: batch,
                        knownStates: [:],
                        assetAccess: assetAccess,
                        cancellationToken: ClipboardSearchCancellationToken()
                    )
                }.value
                indexedCount += batch.count
                updateStatus(
                    ClipboardSearchStatus(
                        indexGeneration: status.indexGeneration,
                        indexedItemCount: indexedCount,
                        totalItemCount: ordered.count,
                        pendingAssetCount: pendingCount,
                        phase: .recovering,
                        fuzzyPhase: .cold
                    ))
                await Task.yield()
            }
            try await BlockingDatabaseExecutor.task(priority: .utility) {
                try shadow.recordIndexedHistoryRevision(historyRevision)
            }.value
            guard latestReconcileContext?.historyRevision == historyRevision else {
                throw CancellationError()
            }
            let committed = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try shadow.committedState()
            }.value
            try await BlockingDatabaseExecutor.task(priority: .utility) {
                try shadow.checkpointForActivation()
            }.value
            let activated = try await BlockingDatabaseExecutor.task(priority: .utility) {
                try ClipboardSearchDatabase(databaseURL: shadowURL, openMode: .openExisting)
            }.value
            let previousDatabaseURL =
                activeDatabaseURL
                ?? (FileManager.default.fileExists(atPath: databaseURL.path)
                    ? databaseURL : nil)
            if let vocabularyWarmupTask {
                await vocabularyWarmupTask.value
            }
            if let integrityCheckTask {
                integrityCheckTask.cancel()
                databaseHandle.currentDatabase()?.interruptMaintenance()
                await integrityCheckTask.value
                self.integrityCheckTask = nil
            }
            isSwitchingDatabase = true
            await searchLane.cancelAndDrain()
            await snippetLane.cancelAndDrain()
            do {
                try persistActiveManifest(databaseURL: shadowURL)
            } catch {
                isSwitchingDatabase = false
                throw error
            }
            let previousDatabase = databaseHandle.replaceDatabase(activated)
            activeDatabaseURL = shadowURL
            isSwitchingDatabase = false
            if let previousDatabaseURL, previousDatabaseURL != shadowURL {
                Self.removeInactiveIndexFiles(
                    at: previousDatabaseURL,
                    afterClosing: previousDatabase
                )
            }
            indexedHistoryRevision = historyRevision
            needsFullReconcile = false
            databaseRetryTask?.cancel()
            databaseRetryTask = nil
            databaseRetryAttempt = 0
            updateStatus(
                ClipboardSearchStatus(
                    indexGeneration: committed.indexGeneration,
                    indexedItemCount: ordered.count,
                    totalItemCount: ordered.count,
                    pendingAssetCount: pendingCount,
                    phase: .ready,
                    fuzzyPhase: .cold
                ))
            schedulePendingAssetRetries(
                historyRevision: historyRevision
            )
            scheduleIntegrityCheck(database: activated)
        } catch is CancellationError {
            isSwitchingDatabase = false
            // A newer desired snapshot owns the next reconcile.
        } catch {
            isSwitchingDatabase = false
            needsFullReconcile = true
            await handleDatabaseError(error, totalItemCount: snapshot.count)
        }
        return status
    }

    private nonisolated static func removeInactiveIndexFiles(at databaseURL: URL) {
        let fileManager = FileManager.default
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ] where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                BufferLogger.persistence.error(
                    "Failed to remove inactive search index file: \(url.lastPathComponent, privacy: .public)"
                )
            }
        }
    }

    private nonisolated static func removeInactiveIndexFiles(
        at databaseURL: URL,
        afterClosing database: ClipboardSearchDatabase?
    ) {
        BlockingDatabaseExecutor.task(priority: .background) {
            // A reconcile that discovered an index gap can still have a local
            // reference to the previous database on its suspended Swift stack.
            // Explicitly close the shared connection owner before unlinking its
            // database, WAL, and SHM files. Waiting for a weak reference to turn
            // nil is insufficient because Swift clears it before deinit has
            // necessarily finished closing every SQLite handle.
            database?.close()
            removeInactiveIndexFiles(at: databaseURL)
        }
    }

    private static func indexBatches(items: [ClipboardItem]) -> [[ClipboardItem]] {
        var result: [[ClipboardItem]] = []
        var batch: [ClipboardItem] = []
        var estimatedBytes = 0
        for item in items {
            let itemBytes = item.originalSizeBytes ?? item.textContent?.utf8.count ?? 0
            if !batch.isEmpty, batch.count >= 100 || estimatedBytes + itemBytes > 8 * 1_024 * 1_024 {
                result.append(batch)
                batch = []
                estimatedBytes = 0
            }
            batch.append(item)
            estimatedBytes += itemBytes
        }
        if !batch.isEmpty { result.append(batch) }
        return result
    }

    private func schedulePendingAssetRetries(
        historyRevision: UInt64
    ) {
        guard status.pendingAssetCount > 0 else {
            pendingAssetRetryTask?.cancel()
            pendingAssetRetryTask = nil
            return
        }
        guard pendingAssetRetryTask == nil else { return }
        pendingAssetRetryTask = Task { [weak self] in
            for delay in [Duration.seconds(5), .seconds(30), .seconds(300)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self, !Task.isCancelled,
                    let context = await self.pendingAssetRetryContext(
                        for: historyRevision
                    )
                else { return }
                let nextStatus = await self.reconcile(
                    snapshot: context.snapshot,
                    historyRevision: context.historyRevision,
                    assetAccess: context.assetAccess
                )
                if nextStatus.pendingAssetCount == 0 {
                    await self.finishPendingAssetRetries()
                    return
                }
            }
            await self?.finishPendingAssetRetries()
        }
    }

    private func pendingAssetRetryContext(
        for historyRevision: UInt64
    ) -> ClipboardSearchReconcileContext? {
        guard indexedHistoryRevision == historyRevision,
            latestReconcileContext?.historyRevision == historyRevision
        else { return nil }
        return latestReconcileContext
    }

    private func finishPendingAssetRetries() {
        pendingAssetRetryTask = nil
    }
}

struct ClipboardPersistentFuzzyVocabulary {
    struct PersistedNode {
        let databaseID: Int64
        let term: String
        let parentDatabaseID: Int64?
        let edgeDistance: Int?
    }

    struct Insertion {
        let nodeIndex: Int
        let parentDatabaseID: Int64?
        let edgeDistance: Int
    }

    struct Candidate {
        let term: String
        let distance: Int
    }

    private struct Node {
        let term: String
        var databaseID: Int64?
        var children: [Int: Int]
    }

    private var nodes: [Node] = []
    private var nodeIndexByTerm: [String: Int] = [:]

    init() {}

    init(persistedNodes: [PersistedNode]) {
        var indexByDatabaseID: [Int64: Int] = [:]
        for persisted in persistedNodes {
            let index = nodes.count
            nodes.append(Node(term: persisted.term, databaseID: persisted.databaseID, children: [:]))
            nodeIndexByTerm[persisted.term] = index
            indexByDatabaseID[persisted.databaseID] = index
        }
        for persisted in persistedNodes {
            guard let parentID = persisted.parentDatabaseID,
                let edgeDistance = persisted.edgeDistance,
                let parentIndex = indexByDatabaseID[parentID],
                let childIndex = indexByDatabaseID[persisted.databaseID]
            else { continue }
            nodes[parentIndex].children[edgeDistance] = childIndex
        }
    }

    mutating func insert(_ term: String) -> Insertion? {
        guard nodeIndexByTerm[term] == nil else { return nil }
        guard !nodes.isEmpty else {
            nodes.append(Node(term: term, databaseID: nil, children: [:]))
            nodeIndexByTerm[term] = 0
            return Insertion(nodeIndex: 0, parentDatabaseID: nil, edgeDistance: 0)
        }

        var nodeIndex = 0
        while true {
            let distance = ClipboardTextMatcher.damerauLevenshteinDistance(term, nodes[nodeIndex].term)
            if let childIndex = nodes[nodeIndex].children[distance] {
                nodeIndex = childIndex
                continue
            }
            let newIndex = nodes.count
            let parentDatabaseID = nodes[nodeIndex].databaseID
            nodes.append(Node(term: term, databaseID: nil, children: [:]))
            nodes[nodeIndex].children[distance] = newIndex
            nodeIndexByTerm[term] = newIndex
            return Insertion(
                nodeIndex: newIndex,
                parentDatabaseID: parentDatabaseID,
                edgeDistance: distance
            )
        }
    }

    mutating func assignDatabaseID(_ databaseID: Int64, toNodeAt index: Int) {
        guard nodes.indices.contains(index) else { return }
        nodes[index].databaseID = databaseID
    }

    func candidates(for term: String, maximumDistance: Int) -> [Candidate] {
        guard !nodes.isEmpty else { return [] }
        var stack = [0]
        var candidates: [Candidate] = []
        while let index = stack.popLast() {
            let node = nodes[index]
            let distance = ClipboardTextMatcher.damerauLevenshteinDistance(term, node.term)
            if distance <= maximumDistance {
                candidates.append(Candidate(term: node.term, distance: distance))
            }
            let lowerBound = max(0, distance - maximumDistance)
            let upperBound = distance + maximumDistance
            for (edgeDistance, childIndex) in node.children
            where edgeDistance >= lowerBound && edgeDistance <= upperBound {
                stack.append(childIndex)
            }
        }
        return candidates.sorted {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.term < $1.term
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
