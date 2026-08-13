import XCTest

@testable import Buffer

@MainActor
final class HistoryViewModelQuickPasteTests: XCTestCase {
    func testQuickPasteUsesPinnedSectionByDefault() async throws {
        let settings = makeHistoryTestSettings()
        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: settings.quickPasteEnabled,
                numberingStart: settings.quickPasteNumberingStart,
                entryCount: 3
            )
        )
        let store = makeHistoryTestStore(settings: settings)

        let pinned = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "pinned")
        let first = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "first")
        let second = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "second")
        await populateStore(store, with: [pinned, first, second])

        try await store.togglePin(for: pinned)
        await eventually {
            store.items.first(where: { $0.id == pinned.id })?.isPinned == true
        }

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[pinned.id], 1)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[second.id], 2)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[first.id], 3)
        XCTAssertEqual(viewModel.performQuickPaste(at: 0)?.id, pinned.id)
    }

    func testQuickPasteCanStartAtNormalEntries() async throws {
        let settings = makeHistoryTestSettings()
        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: settings.quickPasteEnabled,
                numberingStart: .normalEntries,
                entryCount: 2
            )
        )
        let store = makeHistoryTestStore(settings: settings)

        let pinned = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 1), textContent: "pinned")
        let first = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 2), textContent: "first")
        let second = ClipboardItem(type: .text, timestamp: Date(timeIntervalSince1970: 3), textContent: "second")
        await populateStore(store, with: [pinned, first, second])

        try await store.togglePin(for: pinned)
        await eventually {
            store.items.first(where: { $0.id == pinned.id })?.isPinned == true
        }

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)

        XCTAssertNil(viewModel.quickPasteBadgeNumberByItemID[pinned.id])
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[second.id], 1)
        XCTAssertEqual(viewModel.quickPasteBadgeNumberByItemID[first.id], 2)
        XCTAssertEqual(viewModel.performQuickPaste(at: 0)?.id, second.id)
        XCTAssertEqual(viewModel.performQuickPaste(at: 1)?.id, first.id)
        XCTAssertNil(viewModel.performQuickPaste(at: 2))
    }

    func testQuickPasteCanBeDisabled() async {
        let settings = makeHistoryTestSettings()
        settings.setQuickPasteSettings(
            QuickPasteSettings(
                enabled: false,
                numberingStart: settings.quickPasteNumberingStart,
                entryCount: settings.quickPasteEntryCount
            )
        )
        let store = makeHistoryTestStore(settings: settings)
        let item = ClipboardItem.text("only")
        await populateStore(store, with: [item])

        let viewModel = makeHistoryTestViewModel(store: store, settings: settings)
        viewModel.handleQuickPasteModifierFlagsChange(.command)

        XCTAssertTrue(viewModel.quickPasteBadgeNumberByItemID.isEmpty)
        XCTAssertNil(viewModel.performQuickPaste(at: 0))
        XCTAssertFalse(viewModel.showsQuickPasteNumbers)
    }
}
