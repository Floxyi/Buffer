import AppKit
import XCTest

@testable import Buffer

@MainActor
final class HistoryWindowLifecycleTests: XCTestCase {
    func testRegainingKeyAfterSheetDoesNotReapplyWindowOpenScrollPolicy() async throws {
        let settings = makeHistoryTestSettings()
        settings.historyWindowOpenBehavior = .selectFirstNonPinnedItem
        let store = makeHistoryTestStore(settings: settings)
        let items = (0..<80).map { index in
            ClipboardItem(
                type: .text,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                textContent: "item-\(index)"
            )
        }
        await populateStore(store, with: items)

        let controller = HistoryWindowController(
            store: store,
            settingsManager: settings,
            activeApplicationProvider: WindowLifecycleActiveApplicationProvider(),
            pasteController: WindowLifecyclePasteController(),
            ocrService: FakeOCRService(result: ""),
            windowConfiguration: .ephemeral,
            suppressCapturedChange: { _ in }
        )
        controller.showWindow(
            nil,
            focusSearch: false,
            activateApp: false,
            suppressQuickPasteUntilModifiersReleased: false
        )
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        await eventually {
            window.contentView?.layoutSubtreeIfNeeded()
            return window.contentView?.windowLifecycleDescendants(of: NSScrollView.self).contains(where: {
                guard let documentView = $0.documentView else { return false }
                return documentView.frame.height > $0.contentView.bounds.height * 2
            }) == true
        }

        let listScrollView = try XCTUnwrap(
            window.contentView?.windowLifecycleDescendants(of: NSScrollView.self).first(where: {
                guard let documentView = $0.documentView else { return false }
                return documentView.frame.height > $0.contentView.bounds.height * 2
            })
        )
        for _ in 0..<20 {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        scroll(listScrollView, to: 1_400)
        for _ in 0..<10 {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(
            listScrollView.contentView.bounds.minY,
            1_400,
            accuracy: 1,
            "The initial window-open scroll must be settled before presenting the sheet"
        )

        let keyEventRecorder = WindowLifecycleKeyEventRecorder(window: window)
        let confirmationController = HistoryDeleteConfirmationController()
        confirmationController.presentDeleteConfirmation(selectionCount: 1) {}
        await eventually { window.attachedSheet != nil }

        let sheet = try XCTUnwrap(window.attachedSheet)
        window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        await eventually { window.attachedSheet == nil && !confirmationController.isPresenting }
        await eventually { keyEventRecorder.didBecomeKeyCount > 0 }

        for _ in 0..<20 {
            await Task.yield()
            window.contentView?.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(
            listScrollView.contentView.bounds.minY,
            1_400,
            accuracy: 1,
            "A sheet dismissal must not be interpreted as reopening the history window"
        )
    }

    private func scroll(_ scrollView: NSScrollView, to offset: CGFloat) {
        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: offset,
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )
        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)
        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

@MainActor
private final class WindowLifecycleKeyEventRecorder: NSObject {
    private(set) var didBecomeKeyCount = 0

    init(window: NSWindow) {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        didBecomeKeyCount += 1
    }
}

@MainActor
private final class WindowLifecycleActiveApplicationProvider: ActiveApplicationProviding {
    var currentApplication: NSRunningApplication?
    var currentApplicationInfo = SourceApplicationInfo(
        name: nil,
        bundleIdentifier: nil,
        bundlePath: nil
    )
}

@MainActor
private final class WindowLifecyclePasteController: PasteControlling {
    var hasPostEventAccess: Bool { true }

    func applicationTarget(for application: NSRunningApplication?) -> ApplicationTarget? { nil }

    func preparePastePlan(for items: [ClipboardItem]) async throws -> PastePlan {
        PastePlan(id: UUID(), steps: [], temporaryAssetSessionID: nil)
    }

    func executePaste(
        _ plan: PastePlan,
        target: ApplicationTarget?,
        suppressCapture: @escaping @MainActor (PasteboardWriteReceipt) -> Void
    ) async -> PasteOutcome {
        .success
    }

    func copyToClipboard(_ items: [ClipboardItem]) async throws -> PasteboardWriteReceipt {
        PasteboardWriteReceipt(changeCount: 0)
    }

    func cancelPaste() {}
    func completePastePlan(_ plan: PastePlan) {}
    func discardPastePlan(_ plan: PastePlan) {}
    func requestPostEventAccess() -> Bool { true }
    func saveImageToDisk(_ image: NSImage) {}
}

extension NSView {
    fileprivate func windowLifecycleDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        var matches: [ViewType] = []
        if let matchingView = self as? ViewType {
            matches.append(matchingView)
        }
        for subview in subviews {
            matches.append(contentsOf: subview.windowLifecycleDescendants(of: type))
        }
        return matches
    }
}
