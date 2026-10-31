import SQLite3
import XCTest

@testable import Buffer

final class ClipboardSearchTests: XCTestCase {

    func testOpeningOlderSearchSchemaDoesNotMigrateOrDeleteIt() throws {
        let paths = TestStorageFactory.makePaths()
        try FileManager.default.createDirectory(
            at: paths.searchDirectory,
            withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(paths.searchDatabaseURL.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        XCTAssertEqual(
            sqlite3_exec(
                connection,
                "CREATE TABLE legacy_marker(value TEXT); PRAGMA user_version = 5;",
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )
        sqlite3_close(connection)
        connection = nil

        XCTAssertThrowsError(
            try ClipboardSearchDatabase(
                databaseURL: paths.searchDatabaseURL,
                openMode: .openExisting
            )
        ) { error in
            XCTAssertEqual(
                error as? SearchDatabaseValidationError,
                .schemaMismatch(found: 5, expected: ClipboardSearchSchema.currentVersion)
            )
        }

        XCTAssertEqual(sqlite3_open(paths.searchDatabaseURL.path, &connection), SQLITE_OK)
        var markerCount = 0
        let callback:
            @convention(c) (
                UnsafeMutableRawPointer?, Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
                UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            ) -> Int32 = { context, _, _, _ in
                context?.assumingMemoryBound(to: Int.self).pointee += 1
                return 0
            }
        XCTAssertEqual(
            sqlite3_exec(
                connection,
                "SELECT value FROM legacy_marker",
                callback,
                &markerCount,
                nil
            ),
            SQLITE_OK
        )
        XCTAssertEqual(markerCount, 0)
    }

    func testPersistentSearchWarmStrictAndFuzzyQueriesReturnResults() async throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let items = (0..<10_000).map { number in
            ClipboardItem.text("entry \(number) common searchable content")
        }
        _ = await service.reconcile(
            snapshot: items,
            historyRevision: 0,
            assetAccess: assetStore
        )

        // Lazy fuzzy vocabulary construction is intentionally excluded from warm-query latency.
        _ = try await service.search(
            ClipboardSearchRequest(
                queryGeneration: 0,
                historyRevision: 0,
                query: ClipboardQuery(text: "serachable")
            )
        )

        for query in ["entry 499", "serachable"] {
            let response = try await service.search(
                ClipboardSearchRequest(
                    queryGeneration: 1,
                    historyRevision: 0,
                    query: ClipboardQuery(text: query)
                )
            )
            XCTAssertFalse(response.hits.isEmpty)
        }
    }

    func testSingleInsertReadsNoUnrelatedStoredStatesAtTenThousandItems() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let existing = (0..<10_000).map { ClipboardItem.text("stable entry \($0)") }
        _ = try database.reconcile(items: existing, knownStates: [:], assetAccess: assetStore)
        database.resetDiagnostics()

        let inserted = ClipboardItem.text("new isolated entry")
        _ = try database.apply(
            [.insert(inserted)],
            currentSnapshot: existing + [inserted],
            historyRevision: 1,
            assetAccess: assetStore,
            cancellationToken: ClipboardSearchCancellationToken()
        )

        let diagnostics = database.diagnostics()
        XCTAssertEqual(diagnostics.selectedStoredStateCount, 0)
        XCTAssertLessThan(diagnostics.preparedStatementCount, 50)
        XCTAssertNotNil(try database.storedStates(for: [inserted.id])[inserted.id])
    }

    func testRetryableBeginStepAndCommitFailuresRetryWholeTransaction() throws {
        for target in [
            OneShotSQLiteFaultInjector.Target.begin,
            .step(operation: "insert document"),
            .commitBeforeCall,
        ] {
            let paths = TestStorageFactory.makePaths()
            let assetStore = ClipboardAssetStore(paths: paths)
            assetStore.ensureDirectoriesExist()
            let injector = OneShotSQLiteFaultInjector(target: target, code: SQLITE_BUSY)
            let database = try ClipboardSearchDatabase(
                databaseURL: paths.searchDatabaseURL,
                faultInjector: injector
            )
            let item = ClipboardItem.text("retry-safe \(UUID().uuidString)")

            _ = try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)

            XCTAssertEqual(injector.injectionCount, 1)
            XCTAssertNotNil(try database.storedStates(for: [item.id])[item.id])
        }
    }

    func testFailureAfterCommitIsRecoveredByReadingCommittedDatabase() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let injector = OneShotSQLiteFaultInjector(target: .commitAfterCall, code: SQLITE_IOERR)
        let database = try ClipboardSearchDatabase(
            databaseURL: paths.searchDatabaseURL,
            faultInjector: injector
        )
        let item = ClipboardItem.text("committed before publication failed")

        XCTAssertThrowsError(
            try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)
        ) { error in
            guard case ClipboardSearchServiceError.connectionInvalidated = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let reopened = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        XCTAssertNotNil(try reopened.storedStates(for: [item.id])[item.id])
    }

    func testNonRetryableWriteFailuresNeverPublishPartialDocument() throws {
        for code in [SQLITE_FULL, SQLITE_IOERR, SQLITE_READONLY, SQLITE_PERM] {
            let paths = TestStorageFactory.makePaths()
            let assetStore = ClipboardAssetStore(paths: paths)
            assetStore.ensureDirectoriesExist()
            let baseline = ClipboardItem.text("committed baseline")
            let healthy = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
            _ = try healthy.reconcile(items: [baseline], knownStates: [:], assetAccess: assetStore)

            let injector = OneShotSQLiteFaultInjector(
                target: .step(operation: "insert document"),
                code: code
            )
            let failing = try ClipboardSearchDatabase(
                databaseURL: paths.searchDatabaseURL,
                faultInjector: injector
            )
            let rejected = ClipboardItem.text("must not be partially committed")

            XCTAssertThrowsError(
                try failing.reconcile(items: [rejected], knownStates: [:], assetAccess: assetStore)
            )

            let reopened = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
            let states = try reopened.storedStates(for: [baseline.id, rejected.id])
            XCTAssertNotNil(states[baseline.id])
            XCTAssertNil(states[rejected.id])
        }
    }

    func testRollbackFailureInvalidatesConnectionWithoutPublishingSwiftState() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let injector = ScriptedSQLiteFaultInjector(
            failures: [
                .step(operation: "insert document"): [SQLITE_FULL],
                .rollback: [SQLITE_IOERR],
            ]
        )
        let item = ClipboardItem.text("rollback must fail closed")

        do {
            let database = try ClipboardSearchDatabase(
                databaseURL: paths.searchDatabaseURL,
                faultInjector: injector
            )
            XCTAssertThrowsError(
                try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)
            ) { error in
                guard case ClipboardSearchServiceError.connectionInvalidated = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }

        let reopened = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        XCTAssertNil(try reopened.storedStates(for: [item.id])[item.id])
    }

    func testCorruptAndNotADBExtendedCodesAreClassifiedAsCorruption() throws {
        for code in [SQLITE_CORRUPT, SQLITE_NOTADB] {
            let paths = TestStorageFactory.makePaths()
            let assetStore = ClipboardAssetStore(paths: paths)
            assetStore.ensureDirectoriesExist()
            let injector = OneShotSQLiteFaultInjector(
                target: .step(operation: "insert document"),
                code: code | (7 << 8)
            )
            let database = try ClipboardSearchDatabase(
                databaseURL: paths.searchDatabaseURL,
                faultInjector: injector
            )

            XCTAssertThrowsError(
                try database.reconcile(
                    items: [.text("corruption classification")],
                    knownStates: [:],
                    assetAccess: assetStore
                )
            ) { error in
                guard case ClipboardSearchServiceError.corrupt = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testExactSearchLeavesVocabularyColdUntilFuzzyIsRequested() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let item = ClipboardItem.text("exact searchable content")
        _ = try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)

        let snapshot = try database.search(
            query: ClipboardQuery(text: "searchable"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: false
        )

        XCTAssertEqual(snapshot.hits.map(\.itemID), [item.id])
        XCTAssertFalse(database.isVocabularyLoaded)
    }

    func testBoundedRelevanceRanksSpecificDocumentAheadOfNewerSpam() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let specific = ClipboardItem(
            type: .text,
            timestamp: Date(timeIntervalSince1970: 1),
            textContent: "unique signal"
        )
        let spam = (0..<600).map { index in
            ClipboardItem(
                type: .text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index + 2)),
                textContent: String(repeating: "signal ", count: 500)
            )
        }
        _ = try database.reconcile(
            items: [specific] + spam,
            knownStates: [:],
            assetAccess: assetStore
        )

        let response = try database.search(
            query: ClipboardQuery(text: "signal"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: false
        )

        XCTAssertEqual(response.hits.count, spam.count + 1)
        XCTAssertEqual(response.hits.first?.itemID, specific.id)
        XCTAssertTrue(
            response.hits.allSatisfy {
                $0.rank.relevance.method == .boundedIDFLengthV1
            }
        )
    }

    func testMissingAssetPreservesCommittedContentUntilFileReturns() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let filename = try XCTUnwrap(assetStore.saveText("complete original asset"))
        let item = ClipboardItem.largeText(preview: "partial preview", filename: filename)
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        _ = try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)
        let assetURL = paths.textsDirectory.appendingPathComponent(filename)

        try FileManager.default.removeItem(at: assetURL)
        let pendingCount = try database.apply(
            [.updateContent(item)],
            currentSnapshot: [item],
            historyRevision: 1,
            assetAccess: assetStore,
            cancellationToken: ClipboardSearchCancellationToken()
        )

        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(try database.searchableText(for: item.id), "complete original asset")

        try Data("restored complete asset".utf8).write(to: assetURL, options: .atomic)
        let restoredCount = try database.apply(
            [.updateContent(item)],
            currentSnapshot: [item],
            historyRevision: 2,
            assetAccess: assetStore,
            cancellationToken: ClipboardSearchCancellationToken()
        )
        XCTAssertEqual(restoredCount, 0)
        XCTAssertEqual(try database.searchableText(for: item.id), "restored complete asset")
    }

    func testPersistentSearchUsesExactWordTierForUnorderedTermsInOneField() async throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let sameField = ClipboardItem.text("beta appears before alpha")
        let splitAcrossFields = ClipboardItem(
            sourceApp: "beta",
            content: .text(TextItemContent(inlineText: "alpha"))
        )
        _ = await service.reconcile(
            snapshot: [sameField, splitAcrossFields],
            historyRevision: 0,
            assetAccess: assetStore
        )

        let response = try await service.search(
            ClipboardSearchRequest(
                queryGeneration: 1,
                historyRevision: 0,
                query: ClipboardQuery(text: "alpha beta")
            )
        )

        let result = try XCTUnwrap(response.hits.first { $0.itemID == sameField.id })
        XCTAssertEqual(result.rank.tier, .exactToken)
        XCTAssertEqual(result.evidence.kind.classification, .exact)
        XCTAssertFalse(response.hits.contains { $0.itemID == splitAcrossFields.id })
    }

    func testPersistentSearchRanksGitTokenThenPrefixThenSubstringAndExcludesMit() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let exact = ClipboardItem.text("git commit")
        let prefix = ClipboardItem.text("github repository")
        let substring = ClipboardItem.text("digital document")
        let unrelated = ClipboardItem.text("mit freundlichen Grüßen")
        _ = try database.reconcile(
            items: [unrelated, substring, prefix, exact],
            knownStates: [:],
            assetAccess: assetStore
        )

        let sessionID = ClipboardSearchSessionID()
        let strict = try database.search(
            query: ClipboardQuery(text: "git"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: false,
            sessionID: sessionID,
            phase: .strict
        )
        XCTAssertEqual(strict.hits.map(\.itemID), [exact.id, prefix.id])
        XCTAssertEqual(strict.hits.map(\.evidence.kind), [.exactToken, .prefix])

        let substringResponse = try database.search(
            query: ClipboardQuery(text: "git"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: false,
            sessionID: sessionID,
            phase: .substring,
            excluding: Set(strict.hits.map(\.itemID))
        )
        XCTAssertEqual(substringResponse.hits.map(\.itemID), [substring.id])
        XCTAssertEqual(substringResponse.hits.first?.evidence.kind, .substring)
        XCTAssertFalse(
            (strict.hits + substringResponse.hits).contains { $0.itemID == unrelated.id }
        )
    }

    func testThreeCharacterFuzzyOnlyAcceptsTranspositionAndCarriesWinningEvidence() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let git = ClipboardItem.text("git commit")
        let mit = ClipboardItem.text("mit freundlichen Grüßen")
        _ = try database.reconcile(
            items: [git, mit],
            knownStates: [:],
            assetAccess: assetStore
        )

        let response = try database.search(
            query: ClipboardQuery(text: "gti"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: true,
            phase: .similar
        )

        XCTAssertEqual(response.hits.map(\.itemID), [git.id])
        let evidence = try XCTUnwrap(response.hits.first?.evidence)
        XCTAssertEqual(evidence.kind, .fuzzyCorrection)
        XCTAssertEqual(evidence.terms.first?.normalizedQueryTerm, "gti")
        XCTAssertEqual(evidence.terms.first?.normalizedMatchedTerm, "git")
        XCTAssertEqual(evidence.terms.first?.editDistance, 1)
        XCTAssertGreaterThan(evidence.correctionQuality ?? 0, 0)
    }

    func testTechnicalQueriesNeverEnableFuzzyExpansion() {
        for query in [
            "foo@example.com",
            "https://example.com/path",
            "/usr/local/bin",
            "feature/search_v2",
            "sha256",
            "0123456789",
        ] {
            XCTAssertFalse(
                ClipboardQueryPlan(query).allowsFuzzyMatching,
                "Technical query unexpectedly enabled fuzzy expansion: \(query)"
            )
        }
    }

    func testSearchPublishesOneAtomicResponseWithStrictBeforeSubstring() async throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let git = ClipboardItem.text("git commit")
        let digital = ClipboardItem.text("digital document")
        _ = await service.reconcile(
            snapshot: [git, digital],
            historyRevision: 7,
            assetAccess: assetStore
        )

        let response = try await service.search(
            ClipboardSearchRequest(
                queryGeneration: 11,
                historyRevision: 7,
                query: ClipboardQuery(text: "git")
            )
        )

        XCTAssertEqual(response.session.queryGeneration, 11)
        XCTAssertEqual(response.hits.map(\.itemID), [git.id, digital.id])
        XCTAssertEqual(response.hits.map(\.evidence.kind), [.exactToken, .substring])
    }

    func testDeepUnicodeSnippetIsBoundedHighlightedAndGenerationTagged() throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let database = try ClipboardSearchDatabase(databaseURL: paths.searchDatabaseURL)
        let item = ClipboardItem.text(
            String(repeating: "long filler payload ", count: 60_000)
                + "Café needle near the end"
        )
        _ = try database.reconcile(items: [item], knownStates: [:], assetAccess: assetStore)
        let sessionID = ClipboardSearchSessionID()
        let response = try database.search(
            query: ClipboardQuery(text: "cafe"),
            cancellationToken: ClipboardSearchCancellationToken(),
            includeFuzzy: false,
            sessionID: sessionID,
            phase: .strict
        )
        let hit = try XCTUnwrap(response.hits.first)

        let snippetResponse = try database.snippets(
            for: [hit],
            cancellationToken: ClipboardSearchCancellationToken()
        )
        let snippet = try XCTUnwrap(snippetResponse.snippets[item.id])
        XCTAssertEqual(snippet.sessionID, sessionID)
        XCTAssertEqual(snippet.field, .content)
        XCTAssertLessThanOrEqual(snippet.text.count, 120)
        XCTAssertLessThanOrEqual(snippet.text.utf8.count, 512)
        XCTAssertTrue(snippet.segments.contains(where: \.isHighlighted))
        XCTAssertTrue(
            snippet.segments.filter(\.isHighlighted).map(\.text).joined()
                .localizedCaseInsensitiveContains("café")
        )
    }

    func testCancellingSearchTaskCancelsSQLiteWork() async throws {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let items = (0..<10_000).map { number in
            ClipboardItem.text("common searchable content \(number)")
        }
        _ = await service.reconcile(
            snapshot: items,
            historyRevision: 0,
            assetAccess: assetStore
        )

        let task = Task {
            try await service.search(
                ClipboardSearchRequest(
                    queryGeneration: 1,
                    historyRevision: 0,
                    query: ClipboardQuery(text: "common")
                )
            )
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled logical search must not publish a response")
        } catch is CancellationError {
            // Expected: task cancellation reaches sqlite3_interrupt/progress handling.
        }
    }

    func testPersistentSubstringSearchHandlesDiacriticsPunctuationLinksAndEmailAddresses() async {
        let paths = TestStorageFactory.makePaths()
        let assetStore = ClipboardAssetStore(paths: paths)
        assetStore.ensureDirectoriesExist()
        let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
        let item = ClipboardItem.text(
            "Café — docs at https://example.com/a-b?q=1 or mail Person+tag@example.com."
        )
        _ = await service.reconcile(
            snapshot: [item],
            historyRevision: 0,
            assetAccess: assetStore
        )

        for query in ["CAFÉ", "example.com/a-b?q=1", "Person+tag@example.com"] {
            let response = try? await service.search(
                ClipboardSearchRequest(
                    queryGeneration: 1,
                    historyRevision: 0,
                    query: ClipboardQuery(text: query)
                )
            )
            XCTAssertTrue(response?.hits.contains { $0.itemID == item.id } == true, query)
        }
    }

    func testOptInPersistentSearchBenchmark() async throws {
        #if BUFFER_SEARCH_BENCHMARK
            let paths = TestStorageFactory.makePaths(testName: "persistent-search-benchmark")
            try? FileManager.default.removeItem(at: paths.storageDirectory)
            let assetStore = ClipboardAssetStore(paths: paths)
            assetStore.ensureDirectoriesExist()
            let measuredAssets = BenchmarkSearchAssetAccess(base: assetStore)
            var items = (0..<9_800).map { number in
                ClipboardItem.text("benchmark common short entry \(number)")
            }
            let longPrefix =
                String(repeating: "filler content payload segment ", count: 34_000)
                + " benchmark common "
            for number in 0..<200 {
                let body = longPrefix + " deep-needle-\(String(format: "%05d", number))"
                let filename = try XCTUnwrap(assetStore.saveText(body))
                items.append(.largeText(preview: "benchmark common", filename: filename))
            }

            let service = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
            let indexingStart = CFAbsoluteTimeGetCurrent()
            _ = await service.reconcile(
                snapshot: items,
                historyRevision: 1,
                assetAccess: measuredAssets
            )
            let indexingDuration = CFAbsoluteTimeGetCurrent() - indexingStart

            // Exclude the intentional single-flight vocabulary construction from
            // warm fuzzy latency, while still reporting it through indexing/RSS.
            _ = try await service.search(
                ClipboardSearchRequest(
                    queryGeneration: 0,
                    historyRevision: 1,
                    query: ClipboardQuery(text: "benchmrk")
                )
            )

            var generation: UInt64 = 0
            for (name, text) in [
                ("selective-exact", "deep-needle-00199"),
                ("broad-exact", "benchmark common"),
                ("pathological-substring", "ent"),
                ("pathological-prefix", "seg"),
                ("fuzzy", "benchmrk"),
            ] {
                var samples: [TimeInterval] = []
                var lastResponse: ClipboardSearchResponse?
                for _ in 0..<50 {
                    generation &+= 1
                    let start = CFAbsoluteTimeGetCurrent()
                    lastResponse = try await service.search(
                        ClipboardSearchRequest(
                            queryGeneration: generation,
                            historyRevision: 1,
                            query: ClipboardQuery(text: text)
                        )
                    )
                    samples.append(CFAbsoluteTimeGetCurrent() - start)
                }
                await printBenchmark(name: name, samples: samples)
                let methods = Set(
                    lastResponse?.hits.map(\.rank.relevance.method.rawValue) ?? []
                ).sorted()
                await recordBenchmark(
                    "BUFFER_SEARCH_BENCHMARK \(name)_hits=\(lastResponse?.totalCount ?? 0) "
                        + "relevance_methods=\(methods)"
                )
            }

            let largeBody = String(repeating: "ten megabyte incremental content ", count: 330_000)
            let largeFilename = try XCTUnwrap(assetStore.saveText(largeBody))
            let largeItem = ClipboardItem.largeText(
                preview: "ten megabyte incremental content",
                filename: largeFilename
            )
            let incrementalStart = CFAbsoluteTimeGetCurrent()
            _ = await service.apply(
                ClipboardSearchChangeSet(historyRevision: 2, changes: [.insert(largeItem)]),
                currentSnapshot: [largeItem] + items,
                assetAccess: measuredAssets
            )
            let incrementalDuration = CFAbsoluteTimeGetCurrent() - incrementalStart

            let restartAssets = BenchmarkSearchAssetAccess(base: assetStore)
            let restartedService = ClipboardSearchService(databaseURL: paths.searchDatabaseURL)
            let restartStart = CFAbsoluteTimeGetCurrent()
            _ = await restartedService.reconcile(
                snapshot: [largeItem] + items,
                historyRevision: 2,
                assetAccess: restartAssets
            )
            let restartDuration = CFAbsoluteTimeGetCurrent() - restartStart
            let walURL = URL(fileURLWithPath: paths.searchDatabaseURL.path + "-wal")
            let walBytes = (try? walURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            await recordBenchmark(
                "BUFFER_SEARCH_BENCHMARK indexing_s=\(indexingDuration) "
                    + "incremental_10mib_s=\(incrementalDuration) "
                    + "restart_s=\(restartDuration) initial_asset_reads=\(measuredAssets.searchReadCount) "
                    + "restart_asset_reads=\(restartAssets.searchReadCount) "
                    + "initial_stats=\(measuredAssets.searchStatCount) "
                    + "restart_stats=\(restartAssets.searchStatCount) wal_bytes=\(walBytes)"
            )
            XCTAssertEqual(restartAssets.searchReadCount, 0)
        #else
            throw XCTSkip("Run through scripts/benchmark-search.sh")
        #endif
    }

    func testPerformanceDiagnosticsRetainOnlyRecentSamples() {
        BufferPerformanceDiagnostics.reset()

        for _ in 0..<(BufferPerformanceDiagnostics.sampleLimit + 50) {
            let token = BufferPerformanceDiagnostics.begin(.historyFilter)
            BufferPerformanceDiagnostics.end(token)
        }

        XCTAssertEqual(
            BufferPerformanceDiagnostics.samples(for: .historyFilter).count,
            BufferPerformanceDiagnostics.sampleLimit
        )
    }

    private func printBenchmark(name: String, samples: [TimeInterval]) async {
        let sorted = samples.sorted()
        func percentile(_ value: Double) -> Double {
            let index = min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * value)) - 1))
            return sorted[index] * 1_000
        }
        await recordBenchmark(
            "BUFFER_SEARCH_BENCHMARK query=\(name) repetitions=\(samples.count) "
                + "p50_ms=\(percentile(0.50)) p95_ms=\(percentile(0.95)) "
                + "p99_ms=\(percentile(0.99))"
        )
    }

    private func recordBenchmark(_ value: String) async {
        print(value)
        await MainActor.run {
            XCTContext.runActivity(named: value) { _ in }
        }
    }
}

private final class OneShotSQLiteFaultInjector: ClipboardSQLiteFaultInjecting, @unchecked Sendable {
    enum Target: Sendable {
        case begin
        case step(operation: SQLiteOperation)
        case commitBeforeCall
        case commitAfterCall
    }

    private let target: Target
    private let code: Int32
    private let lock = NSLock()
    private var remaining = 1
    private var count = 0

    init(target: Target, code: Int32) {
        self.target = target
        self.code = code
    }

    var injectionCount: Int { lock.withLock { count } }

    func injectedCode(at point: ClipboardSQLiteFaultPoint) -> Int32? {
        lock.withLock {
            guard remaining > 0, matches(point) else { return nil }
            remaining -= 1
            count += 1
            return code
        }
    }

    private func matches(_ point: ClipboardSQLiteFaultPoint) -> Bool {
        switch (target, point) {
        case (.begin, .begin), (.commitBeforeCall, .commitBeforeCall),
            (.commitAfterCall, .commitAfterCall):
            return true
        case (.step(let expected), .step(let operation)):
            return expected == operation
        default:
            return false
        }
    }
}

private final class ScriptedSQLiteFaultInjector: ClipboardSQLiteFaultInjecting, @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [ClipboardSQLiteFaultPoint: [Int32]]

    init(failures: [ClipboardSQLiteFaultPoint: [Int32]]) {
        self.failures = failures
    }

    func injectedCode(at point: ClipboardSQLiteFaultPoint) -> Int32? {
        lock.withLock {
            guard var codes = failures[point], !codes.isEmpty else { return nil }
            let code = codes.removeFirst()
            failures[point] = codes
            return code
        }
    }
}

private final class BenchmarkSearchAssetAccess: ClipboardAssetAccessing, @unchecked Sendable {
    private let base: ClipboardAssetStore
    private let lock = NSLock()
    private var readCount = 0
    private var statCount = 0

    init(base: ClipboardAssetStore) {
        self.base = base
    }

    var searchReadCount: Int { lock.withLock { readCount } }
    var searchStatCount: Int { lock.withLock { statCount } }

    func fingerprint(for item: ClipboardItem) throws -> ClipboardSearchAssetFingerprint {
        lock.withLock { statCount += 1 }
        return try base.fingerprint(for: item)
    }

    func image(for item: ClipboardItem) -> NSImage? { base.image(for: item) }
    func imageData(for item: ClipboardItem) -> Data? { base.imageData(for: item) }
    func thumbnail(for item: ClipboardItem, maxPixelSize: CGFloat) -> NSImage? {
        base.thumbnail(for: item, maxPixelSize: maxPixelSize)
    }
    func imageDimensions(for item: ClipboardItem) -> String? { base.imageDimensions(for: item) }
    func saveImage(_ data: Data) -> String? { base.saveImage(data) }
    func saveText(_ text: String) -> String? { base.saveText(text) }
    func deleteImage(named filename: String) { base.deleteImage(named: filename) }
    func deleteText(named filename: String) { base.deleteText(named: filename) }
    func fullText(for item: ClipboardItem) -> String? { base.fullText(for: item) }
    func textChunk(for item: ClipboardItem, charCount: Int) -> ClipboardTextChunk? {
        base.textChunk(for: item, charCount: charCount)
    }
    func itemSize(for item: ClipboardItem) -> Int? { base.itemSize(for: item) }

    func snapshot(
        for item: ClipboardItem,
        checkCancellation: @Sendable () throws -> Void
    ) throws -> ClipboardSearchAssetSnapshot {
        lock.withLock { readCount += 1 }
        return try base.snapshot(for: item, checkCancellation: checkCancellation)
    }
}
