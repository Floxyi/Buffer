import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ClipboardWatcherTests: XCTestCase {
    func testIgnoreNextCapturedChangeSkipsOnlyNextClipboardUpdate() async {
        let context = makeWatcherContext()
        context.pasteboard.text = "ignored"
        context.pasteboard.changeCount = 1

        context.watcher.suppressCapture(forChangeCount: 1)
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.isEmpty
        }

        context.pasteboard.text = "captured"
        context.pasteboard.changeCount = 2
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.map(\.textContent) == ["captured"]
        }
    }

    func testSuppressionReceiptDoesNotHideAUsersLaterClipboardWrite() async {
        let context = makeWatcherContext()
        context.watcher.suppressCapture(forChangeCount: 1)

        context.pasteboard.text = "user content"
        context.pasteboard.changeCount = 2
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.map(\.textContent) == ["user content"]
        }
    }

    func testExcludedSourceApplicationPreventsCapture() async {
        let sourceApp = SourceApplicationInfo(
            name: "Notes",
            bundleIdentifier: "com.apple.Notes",
            bundlePath: "/Applications/Notes.app"
        )
        let context = makeWatcherContext(sourceApp: sourceApp)
        context.settings.addExcludedApp(
            ExcludedApp(
                name: "Notes",
                bundleIdentifier: sourceApp.bundleIdentifier,
                bundlePath: sourceApp.bundlePath!
            )
        )

        context.pasteboard.text = "blocked"
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.isEmpty
        }
    }

    func testDuplicateTextHashDoesNotAddSecondItem() async {
        let context = makeWatcherContext()
        context.pasteboard.text = "same text"
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.count == 1
        }

        context.pasteboard.changeCount = 2
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.count == 1
        }
    }

    func testTrailingWhitespaceModeNormalizesBeforeCaptureAndDuplicateDetection() async {
        let context = makeWatcherContext()
        context.settings.setClipboardWhitespaceMode(.trimTrailingSpacesAndTabs)
        context.pasteboard.text = "first  \n\tsecond\t "
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.first?.textContent == "first\n\tsecond"
        }

        XCTAssertEqual(
            context.pasteboard.text,
            "first  \n\tsecond\t ",
            "Capture normalization must not rewrite the system clipboard"
        )

        context.pasteboard.text = "first\n\tsecond"
        context.pasteboard.changeCount = 2
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.count == 1
        }
    }

    func testTrailingWhitespaceNormalizationRunsBeforeStructuredClassification() async {
        let context = makeWatcherContext()
        context.settings.setClipboardWhitespaceMode(.trimTrailingSpacesAndTabs)
        context.pasteboard.text = "person@example.com \t"
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.first?.emailPayload?.originalText == "person@example.com"
        }
    }

    func testWhitespaceOnlyCaptureIsIgnoredInTrimmingMode() async {
        let context = makeWatcherContext()
        context.settings.setClipboardWhitespaceMode(.trimTrailingSpacesAndTabs)
        context.pasteboard.text = " \t  "
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await Task.yield()
        XCTAssertTrue(context.store.items.isEmpty)
    }

    func testLargeTextStoresTheSameNormalizedContentUsedForItsPreview() async {
        let context = makeWatcherContext()
        context.settings.setClipboardWhitespaceMode(.trimTrailingSpacesAndTabs)
        let rawText = String(repeating: "content \t\n", count: 7_000) + "final  "
        let expectedText = String(repeating: "content\n", count: 7_000) + "final"
        context.pasteboard.text = rawText
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            guard let item = context.store.items.first else { return false }
            return item.isFileBacked
                && item.textContent == String(expectedText.prefix(ClipboardCaptureSupport.previewLength))
                && context.store.fullText(for: item) == expectedText
        }
    }

    func testImageFileCaptureAddsImageItem() async throws {
        let context = makeWatcherContext()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BufferTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let fileURL = root.appendingPathComponent("captured.png")
        try makePNGData().write(to: fileURL, options: .atomic)

        context.pasteboard.filePaths = [fileURL.path]
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.count == 1 && context.store.items.first?.kind == .image
        }
    }

    func testPauseAndResumeGatePollingAgainstCurrentChangeCount() async {
        let context = makeWatcherContext()
        context.watcher.pause()
        context.pasteboard.text = "paused"
        context.pasteboard.changeCount = 1
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.isEmpty
        }

        context.watcher.resume()
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.isEmpty
        }

        context.pasteboard.text = "after resume"
        context.pasteboard.changeCount = 2
        context.watcher.checkClipboard()

        await eventually {
            context.store.items.map(\.textContent) == ["after resume"]
        }
    }

    func testCanceledCaptureDiscardsImageSavedAfterCancellation() async {
        let worker = ClipboardCaptureWorker()
        let assetStore = SuspendedCaptureAssetStore()
        let imageData = makePNGData()
        let task = Task {
            await worker.processPasteboardImage(
                imageData,
                sourceApp: nil,
                store: assetStore
            )
        }

        await assetStore.waitUntilImageSaveStarts()
        task.cancel()
        await assetStore.finishImageSave(named: "orphan.png")

        let result = await task.value
        guard case .none = result else {
            XCTFail("A canceled capture must not produce a history item")
            return
        }
        let discardedFilenames = await assetStore.discardedImageFilenames()
        XCTAssertEqual(discardedFilenames, ["orphan.png"])
    }

    private func makeWatcherContext(
        sourceApp: SourceApplicationInfo = SourceApplicationInfo(
            name: "Preview",
            bundleIdentifier: "com.apple.Preview",
            bundlePath: "/Applications/Preview.app"
        )
    ) -> WatcherTestContext {
        let settings = SettingsManager(
            defaults: makeTestDefaults(),
            launchAtLoginController: FakeLaunchAtLoginController()
        )
        let store = ClipboardStore(
            settingsManager: settings,
            storagePaths: TestStorageFactory.makePaths()
        )
        let pasteboard = FakeClipboardPasteboard()
        let activeApplicationProvider = FakeActiveApplicationProvider(sourceApp: sourceApp)
        let watcher = ClipboardWatcher(
            store: store,
            settingsManager: settings,
            activeApplicationProvider: activeApplicationProvider,
            pasteboard: pasteboard
        )

        return WatcherTestContext(
            watcher: watcher,
            store: store,
            settings: settings,
            pasteboard: pasteboard
        )
    }
}

private actor SuspendedCaptureAssetStore: ClipboardCaptureAssetPersisting {
    private var imageSaveContinuation: CheckedContinuation<String?, Never>?
    private var discardedImages: [String] = []

    func saveImageAsync(_ data: Data) async -> String? {
        await withCheckedContinuation { continuation in
            imageSaveContinuation = continuation
        }
    }

    func saveTextAsync(_ text: String) async -> String? {
        nil
    }

    func discardCapturedImage(named filename: String) async {
        discardedImages.append(filename)
    }

    func discardCapturedText(named filename: String) async {}

    func waitUntilImageSaveStarts() async {
        while imageSaveContinuation == nil {
            await Task.yield()
        }
    }

    func finishImageSave(named filename: String) {
        imageSaveContinuation?.resume(returning: filename)
        imageSaveContinuation = nil
    }

    func discardedImageFilenames() -> [String] {
        discardedImages
    }
}

@MainActor
private struct WatcherTestContext {
    let watcher: ClipboardWatcher
    let store: ClipboardStore
    let settings: SettingsManager
    let pasteboard: FakeClipboardPasteboard
}

@MainActor
private final class FakeActiveApplicationProvider: ActiveApplicationProviding {
    var currentApplication: NSRunningApplication?
    var currentApplicationInfo: SourceApplicationInfo

    init(sourceApp: SourceApplicationInfo) {
        self.currentApplicationInfo = sourceApp
    }
}

@MainActor
private final class FakeClipboardPasteboard: ClipboardReadingPasteboard {
    var changeCount = 0
    var text: String?
    var filePaths: [String]?
    var imageData: Data?

    func propertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type.rawValue == "NSFilenamesPboardType" {
            return filePaths
        }
        return nil
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        guard type == .string else {
            return nil
        }
        return text
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        guard type == .png || type == .tiff else {
            return nil
        }
        return imageData
    }
}
