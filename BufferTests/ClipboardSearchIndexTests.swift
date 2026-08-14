import XCTest

@testable import Buffer

final class ClipboardSearchIndexTests: XCTestCase {
    func testRebuildRetainsCachedValueForUnchangedContentHash() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("hello")
        var loadCount = 0

        index.rebuild(using: [item]) { currentItem in
            loadCount += 1
            return currentItem.textContent ?? ""
        }
        index.rebuild(using: [item]) { currentItem in
            loadCount += 1
            return (currentItem.textContent ?? "") + " changed"
        }

        XCTAssertEqual(index.searchableText(for: item.id), "hello")
        XCTAssertEqual(loadCount, 1)
    }

    func testRebuildRefreshesEntryWhenContentHashChanges() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem(type: .image, imageFilename: "sample.png", ocrText: nil)
        let updatedItem = item.updatingOCRText("detected text")

        index.rebuild(using: [item]) { _ in "" }
        index.rebuild(using: [updatedItem]) { currentItem in
            currentItem.ocrText ?? ""
        }

        XCTAssertEqual(index.searchableText(for: item.id), "detected text")
    }

    func testRebuildReusesContentWhenOnlySourceMetadataChanges() {
        let original = ClipboardItem(
            sourceApp: "Notes",
            content: .text(
                TextItemContent(inlineText: "preview", fileName: "body.txt")
            )
        )
        let updated = ClipboardItem(
            id: original.id,
            sourceApp: "Preview",
            content: original.content
        )
        var index = ClipboardSearchIndex()
        var loadCount = 0

        index.rebuild(using: [original]) { _ in
            loadCount += 1
            return "file-backed body"
        }
        index.rebuild(using: [updated]) { _ in
            loadCount += 1
            return "should not be loaded"
        }

        XCTAssertEqual(index.searchableText(for: original.id), "file-backed body")
        XCTAssertEqual(loadCount, 1)
        XCTAssertNotNil(searchResult(in: index, for: updated, query: ClipboardQuery(text: "preveiw")))
    }

    func testMatchesUsesNormalizedCaseInsensitiveText() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("CafE")
        index.rebuild(using: [item]) { $0.textContent ?? "" }

        XCTAssertNotNil(searchResult(in: index, for: item, query: ClipboardQuery(text: "cafe")))
    }

    func testTypedQueryReturnsFieldAndOriginalTextRange() throws {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("Café receipt")
        index.rebuild(using: [item]) { $0.textContent ?? "" }

        let result = try XCTUnwrap(searchResult(in: index, for: item, query: ClipboardQuery(text: "cafe")))
        let match = try XCTUnwrap(result.matches.first)

        XCTAssertEqual(match.field, .content)
        XCTAssertEqual(match.classification, .exact)
        XCTAssertEqual(match.ranges.map { String("Café receipt"[$0]) }, ["Café"])
    }

    func testTypedQueryReturnsEveryOriginalTextRange() throws {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem.text("Café and cafe")
        index.rebuild(using: [item]) { $0.textContent ?? "" }

        let result = try XCTUnwrap(searchResult(in: index, for: item, query: ClipboardQuery(text: "cafe")))
        let match = try XCTUnwrap(result.matches.first)

        XCTAssertEqual(match.ranges.map { String("Café and cafe"[$0]) }, ["Café", "cafe"])
    }

    func testTypedQueryAppliesBookmarkAppTypeAndDateFilters() {
        var index = ClipboardSearchIndex()
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let item = ClipboardItem(
            timestamp: timestamp,
            sourceApp: "Notes",
            sourceAppBundleIdentifier: "com.apple.Notes",
            isBookmarked: true,
            content: .text(TextItemContent(inlineText: "meeting notes"))
        )
        index.rebuild(using: [item]) { $0.textContent ?? "" }

        let matchingQuery = ClipboardQuery(
            text: "notes",
            filters: ClipboardFilters(
                requiresBookmark: true,
                sourceBundleIdentifiers: ["com.apple.Notes"],
                kinds: [.text],
                copiedAt: DateInterval(
                    start: timestamp.addingTimeInterval(-1),
                    end: timestamp.addingTimeInterval(1)
                )
            )
        )
        XCTAssertEqual(
            HistoryItemFilter().results(from: [item], query: matchingQuery, searchIndex: index).count,
            1
        )

        var excludedQuery = matchingQuery
        excludedQuery.filters.kinds = [.image]
        XCTAssertTrue(
            HistoryItemFilter().results(from: [item], query: excludedQuery, searchIndex: index).isEmpty
        )
    }

    func testTypedQueryCanExcludeOCRMatches() {
        var index = ClipboardSearchIndex()
        let item = ClipboardItem(
            type: .image,
            imageFilename: "sample.png",
            ocrText: "invoice number"
        )
        index.rebuild(using: [item]) { _ in "" }

        XCTAssertNotNil(
            searchResult(
                in: index,
                for: item,
                query: ClipboardQuery(text: "invoice", includesOCRText: true)
            )
        )
        XCTAssertNil(
            searchResult(
                in: index,
                for: item,
                query: ClipboardQuery(text: "invoice", includesOCRText: false)
            )
        )
    }

    func testFuzzyMatchingAcceptsSingleEditOperationsAndTransposition() {
        let item = ClipboardItem.text("hello")
        let index = makeIndex(for: [item])

        for query in ["helo", "helllo", "hxllo", "hlelo"] {
            let result = searchResult(in: index, for: item, query: ClipboardQuery(text: query))
            XCTAssertEqual(result?.matches.first?.classification, .fuzzy, query)
        }
    }

    func testFuzzyMatchingAcceptsTwoEditsForLongTerms() {
        let item = ClipboardItem.text("searchable")
        let index = makeIndex(for: [item])

        XCTAssertNotNil(
            searchResult(in: index, for: item, query: ClipboardQuery(text: "searxhablz"))
        )
    }

    func testFuzzyMatchingRequiresTermsInOrderWithinOneField() {
        let matching = ClipboardItem.text("alpha middle beta")
        let reversed = ClipboardItem.text("beta middle alpha")
        let splitAcrossFields = ClipboardItem(
            sourceApp: "beta",
            content: .text(TextItemContent(inlineText: "alpha"))
        )
        let items = [matching, reversed, splitAcrossFields]
        let index = makeIndex(for: items)
        let results = index.results(
            for: items.map(\.id),
            query: ClipboardQuery(text: "alhpa btea")
        )

        XCTAssertEqual(Set(results.keys), [matching.id])
    }

    func testFuzzyMatchingRejectsShortNumericUnrelatedAndExcessiveEdits() {
        let shortItem = ClipboardItem.text("cat")
        let numericItem = ClipboardItem.text("code 1234")
        let unrelatedItem = ClipboardItem.text("hello")
        let items = [shortItem, numericItem, unrelatedItem]
        let index = makeIndex(for: items)

        XCTAssertNil(searchResult(in: index, for: shortItem, query: ClipboardQuery(text: "ct")))
        XCTAssertNil(searchResult(in: index, for: numericItem, query: ClipboardQuery(text: "1235")))
        XCTAssertNil(searchResult(in: index, for: unrelatedItem, query: ClipboardQuery(text: "wxyz")))
        XCTAssertNil(searchResult(in: index, for: unrelatedItem, query: ClipboardQuery(text: "hxxxz")))
    }

    func testFuzzyMatchingHonorsSourceApplicationAndOCRInclusion() {
        let item = ClipboardItem(
            sourceApp: "Preview",
            content: .image(ImageItemContent(filename: "sample.png", ocrText: "invoice"))
        )
        let index = makeIndex(for: [item])

        let sourceResult = searchResult(
            in: index,
            for: item,
            query: ClipboardQuery(text: "preveiw")
        )
        XCTAssertEqual(sourceResult?.matches.first?.field, .sourceApplication)

        XCTAssertNotNil(
            searchResult(
                in: index,
                for: item,
                query: ClipboardQuery(text: "inovice", includesOCRText: true)
            )
        )
        XCTAssertNil(
            searchResult(
                in: index,
                for: item,
                query: ClipboardQuery(text: "inovice", includesOCRText: false)
            )
        )
    }

    func testExactMatchIsClassifiedAndScoredAboveFuzzyMatch() throws {
        let exact = ClipboardItem.text("receipt")
        let fuzzy = ClipboardItem.text("reciept")
        let items = [exact, fuzzy]
        let index = makeIndex(for: items)
        let results = index.results(for: items.map(\.id), query: ClipboardQuery(text: "receipt"))
        let exactResult = try XCTUnwrap(results[exact.id])
        let fuzzyResult = try XCTUnwrap(results[fuzzy.id])

        XCTAssertEqual(exactResult.matches.first?.classification, .exact)
        XCTAssertEqual(fuzzyResult.matches.first?.classification, .fuzzy)
        XCTAssertGreaterThan(exactResult.score, fuzzyResult.score)
    }

    func testHistoryFilterPreservesInputOrderInsteadOfRankingByScore() {
        let fuzzy = ClipboardItem.text("reciept")
        let exact = ClipboardItem.text("receipt")
        let items = [fuzzy, exact]
        let index = makeIndex(for: items)

        let results = HistoryItemFilter().results(
            from: items,
            query: ClipboardQuery(text: "receipt"),
            searchIndex: index
        )

        XCTAssertEqual(results.map(\.item.id), [fuzzy.id, exact.id])
        XCTAssertGreaterThan(results[1].result.score, results[0].result.score)
    }

    func testRebuildUpdatesAndRemovesVocabularyOccurrences() {
        let original = ClipboardItem.text("receipt")
        let updated = ClipboardItem(id: original.id, content: .text(TextItemContent(inlineText: "invoice")))
        var index = makeIndex(for: [original])

        XCTAssertNotNil(searchResult(in: index, for: original, query: ClipboardQuery(text: "reciept")))
        index.rebuild(using: [updated]) { $0.textContent ?? "" }
        XCTAssertNil(searchResult(in: index, for: updated, query: ClipboardQuery(text: "reciept")))
        XCTAssertNotNil(searchResult(in: index, for: updated, query: ClipboardQuery(text: "inovice")))

        index.rebuild(using: []) { _ in "" }
        XCTAssertTrue(index.results(for: [updated.id], query: ClipboardQuery(text: "inovice")).isEmpty)
    }

    func testSharedMatcherHighlightsWholeFuzzyWords() {
        let text = "Receipt total today"
        let ranges = ClipboardTextMatcher.highlightedRanges(
            in: text,
            queryPlan: ClipboardQueryPlan("reciept toatl"),
            classification: .fuzzy
        )

        XCTAssertEqual(ranges.map { String(text[$0]) }, ["Receipt", "total"])
    }

    func testFilteringCachedEntriesStaysWithinInteractiveBudget() {
        for itemCount in [1_000, 5_000, 10_000] {
            assertCachedFilterDuration(
                itemCount: itemCount,
                query: "entry 499",
                isLessThan: 0.05
            )
            assertCachedFilterDuration(
                itemCount: itemCount,
                query: "serachable",
                isLessThan: 0.05
            )
        }
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

    private func assertCachedFilterDuration(
        itemCount: Int,
        query: String,
        isLessThan limit: TimeInterval
    ) {
        let items = (0..<itemCount).map { number in
            ClipboardItem.text("entry \(number) common searchable content")
        }
        let index = makeIndex(for: items)

        let start = CFAbsoluteTimeGetCurrent()
        let matches = index.results(for: items.map(\.id), query: ClipboardQuery(text: query))
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertFalse(matches.isEmpty)
        XCTAssertLessThan(
            duration,
            limit,
            "Filtering \(itemCount) cached entries took \(duration)s"
        )
    }

    private func makeIndex(for items: [ClipboardItem]) -> ClipboardSearchIndex {
        var index = ClipboardSearchIndex()
        index.rebuild(using: items) { $0.textContent ?? $0.ocrText ?? "" }
        return index
    }

    private func searchResult(
        in index: ClipboardSearchIndex,
        for item: ClipboardItem,
        query: ClipboardQuery
    ) -> ClipboardSearchResult? {
        index.results(for: [item.id], query: query)[item.id]
    }
}
