import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ClipboardApplicationIconLoaderTests: XCTestCase {
    func testCacheKeyPrefersStableBundleIdentifier() {
        let item = makeItem(
            bundleIdentifier: "com.example.app",
            bundlePath: "/Applications/Example.app"
        )

        XCTAssertEqual(
            ClipboardApplicationIconLoader.cacheKey(for: item),
            "bundle:com.example.app"
        )
    }

    func testCacheKeyFallsBackToBundlePath() {
        let item = makeItem(bundlePath: "/Applications/Example.app")

        XCTAssertEqual(
            ClipboardApplicationIconLoader.cacheKey(for: item),
            "path:/Applications/Example.app"
        )
    }

    func testCacheKeyRejectsEmailItems() throws {
        let sourceApp = SourceApplicationInfo(
            name: "Mail",
            bundleIdentifier: "com.apple.mail",
            bundlePath: "/System/Applications/Mail.app"
        )
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com")),
            sourceApp: sourceApp
        )

        XCTAssertNil(ClipboardApplicationIconLoader.cacheKey(for: item))
    }

    func testRegisteredBundleIdentifierOverridesStaleRecordedPath() async throws {
        let finderBundleIdentifier = "com.apple.finder"
        XCTAssertNotNil(
            NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: finderBundleIdentifier
            )
        )
        let item = makeItem(
            bundleIdentifier: finderBundleIdentifier,
            bundlePath: "/Applications/Removed Finder Copy.app"
        )
        let loader = ClipboardApplicationIconLoader()

        let icon = await loader.loadIcon(for: item)

        XCTAssertNotNil(icon)
    }

    func testMissingRemoteApplicationPathDoesNotProduceGenericLightIcon() async {
        let identifier = "com.buffer-tests.missing-\(UUID().uuidString)"
        let item = makeItem(
            bundleIdentifier: identifier,
            bundlePath: "/Applications/Missing Buffer Test App \(UUID().uuidString).app"
        )
        let loader = ClipboardApplicationIconLoader()

        let icon = await loader.loadIcon(for: item)

        XCTAssertNil(icon)
    }

    func testPreservedCopyRetainsLogicalSizeAndEveryRepresentation() throws {
        let icon = makeMultiRepresentationIcon()
        let expectedRepresentations = representationDescriptors(for: icon)

        let copy = ClipboardApplicationIconLoader.preservedCopy(of: icon)

        XCTAssertFalse(copy === icon)
        XCTAssertEqual(copy.size, icon.size)
        XCTAssertEqual(representationDescriptors(for: copy), expectedRepresentations)
    }

    func testLogicalSizeCopyUsesNativeMenuDimensionsWithoutFlatteningRepresentations() {
        let icon = makeMultiRepresentationIcon()
        let expectedRepresentations = representationDescriptors(for: icon)

        let copy = ClipboardApplicationIconLoader.logicalSizeCopy(of: icon, size: 16)

        XCTAssertEqual(copy.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(representationDescriptors(for: copy), expectedRepresentations)
    }

    func testLoadedIconIsCachedWithoutChangingItsRepresentations() async throws {
        let sourceIcon = makeMultiRepresentationIcon()
        var resolutionCount = 0
        let loader = ClipboardApplicationIconLoader { _ in
            resolutionCount += 1
            return sourceIcon
        }
        let item = makeItem(bundlePath: "/Applications/Example.app")

        let loadedFirstIcon = await loader.loadIcon(for: item)
        let loadedSecondIcon = await loader.loadIcon(for: item)
        let firstIcon = try XCTUnwrap(loadedFirstIcon)
        let secondIcon = try XCTUnwrap(loadedSecondIcon)

        XCTAssertTrue(firstIcon === sourceIcon)
        XCTAssertTrue(secondIcon === sourceIcon)
        XCTAssertEqual(resolutionCount, 1)
        XCTAssertEqual(
            representationDescriptors(for: firstIcon),
            representationDescriptors(for: sourceIcon)
        )
    }

    func testLightAndDarkIconsUseSeparateCacheEntries() async throws {
        let lightIcon = makeTestImage(color: .white)
        let darkIcon = makeTestImage(color: .black)
        var resolvedAppearances: [ClipboardApplicationIconAppearance] = []
        let loader = ClipboardApplicationIconLoader { _, appearance in
            resolvedAppearances.append(appearance)
            return appearance == .dark ? darkIcon : lightIcon
        }
        let item = makeItem(bundlePath: "/Applications/Example.app")

        let firstLightIcon = await loader.loadIcon(for: item, appearance: .light)
        let loadedDarkIcon = await loader.loadIcon(for: item, appearance: .dark)
        let secondLightIcon = await loader.loadIcon(for: item, appearance: .light)

        XCTAssertTrue(try XCTUnwrap(firstLightIcon) === lightIcon)
        XCTAssertTrue(try XCTUnwrap(loadedDarkIcon) === darkIcon)
        XCTAssertTrue(try XCTUnwrap(secondLightIcon) === lightIcon)
        XCTAssertEqual(resolvedAppearances, [.light, .dark])
        XCTAssertTrue(loader.cachedIcon(for: item, appearance: .light) === lightIcon)
        XCTAssertTrue(loader.cachedIcon(for: item, appearance: .dark) === darkIcon)
    }

    func testSystemIconAppearanceChangeInvalidatesCacheAndPublishesRevision() async throws {
        let notificationCenter = NotificationCenter()
        let originalIcon = makeTestImage(color: .white)
        let updatedIcon = makeTestImage(color: .blue)
        var resolutionCount = 0
        let loader = ClipboardApplicationIconLoader(
            notificationCenter: notificationCenter
        ) { _ in
            resolutionCount += 1
            return resolutionCount == 1 ? originalIcon : updatedIcon
        }
        let item = makeItem(bundlePath: "/Applications/Example.app")

        let firstIcon = await loader.loadIcon(for: item)
        XCTAssertTrue(try XCTUnwrap(firstIcon) === originalIcon)
        XCTAssertEqual(loader.iconRevision, 0)

        notificationCenter.post(
            name: .workspaceIconAppearanceConfigurationDidChange,
            object: nil
        )

        XCTAssertEqual(loader.iconRevision, 1)
        XCTAssertNil(loader.cachedIcon(for: item))

        let reloadedIcon = await loader.loadIcon(for: item)
        XCTAssertTrue(try XCTUnwrap(reloadedIcon) === updatedIcon)
        XCTAssertEqual(resolutionCount, 2)
    }

    private func makeItem(
        bundleIdentifier: String? = nil,
        bundlePath: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            sourceAppBundleIdentifier: bundleIdentifier,
            sourceAppBundlePath: bundlePath,
            content: .text(TextItemContent(inlineText: "hello"))
        )
    }

    private func makeMultiRepresentationIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(makeBitmapRepresentation(pixelSize: 32, pointSize: 32))
        image.addRepresentation(makeBitmapRepresentation(pixelSize: 64, pointSize: 32))
        image.addRepresentation(makeBitmapRepresentation(pixelSize: 16, pointSize: 16))
        return image
    }

    private func makeBitmapRepresentation(pixelSize: Int, pointSize: CGFloat) -> NSBitmapImageRep {
        let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        representation.size = NSSize(width: pointSize, height: pointSize)
        return representation
    }

    private func representationDescriptors(for image: NSImage) -> [IconRepresentationDescriptor] {
        image.representations.map {
            IconRepresentationDescriptor(
                pixelsWide: $0.pixelsWide,
                pixelsHigh: $0.pixelsHigh,
                pointSize: $0.size
            )
        }
    }
}

@MainActor
final class ClipboardItemIconLoaderTests: XCTestCase {
    func testWebsiteIconCacheKeyUsesLowercasedHost() {
        let item = ClipboardItem.link(
            URL(string: "https://WWW.Example.COM/path")!,
            originalText: "https://WWW.Example.COM/path"
        )

        XCTAssertEqual(
            ClipboardItemIconLoader.websiteIconCacheKey(for: item),
            "website:www.example.com"
        )
    }

    func testEmailItemsNeverResolveLeadingIcons() async throws {
        let settings = makeHistoryTestSettings()
        let applicationIconLoader = ClipboardApplicationIconLoader { _ in
            XCTFail("Email items must not request application icons")
            return makeTestImage()
        }
        let sourceApp = SourceApplicationInfo(
            name: "Mail",
            bundleIdentifier: "com.apple.mail",
            bundlePath: "/System/Applications/Mail.app"
        )
        let item = ClipboardItem.email(
            try XCTUnwrap(ClipboardEmailValue.parse("person@example.com")),
            sourceApp: sourceApp
        )

        XCTAssertNil(
            ClipboardItemIconLoader.cachedLeadingIcon(
                for: item,
                settings: settings,
                applicationIconLoader: applicationIconLoader
            )
        )
        let loadedIcon = await ClipboardItemIconLoader.loadPreferredLeadingIcon(
            for: item,
            settings: settings,
            applicationIconLoader: applicationIconLoader
        )
        XCTAssertNil(loadedIcon)
    }

    func testCachedLeadingIconUsesNativeApplicationFallbackForLinks() async throws {
        let settings = makeHistoryTestSettings()
        settings.enableWebsitePreviews = false
        let applicationIcon = makeTestImage(size: NSSize(width: 32, height: 32))
        let applicationIconLoader = ClipboardApplicationIconLoader { _ in applicationIcon }
        let item = ClipboardItem(
            sourceAppBundlePath: "/Applications/Example.app",
            content: .link(
                LinkItemContent(
                    url: try XCTUnwrap(URL(string: "https://example.com")),
                    originalText: "https://example.com"
                )
            )
        )
        _ = await applicationIconLoader.loadIcon(for: item)

        let leadingIcon = ClipboardItemIconLoader.cachedLeadingIcon(
            for: item,
            settings: settings,
            applicationIconLoader: applicationIconLoader
        )

        XCTAssertTrue(leadingIcon === applicationIcon)
    }

    func testCachedLeadingIconPrefersWebsiteIconWithoutReplacingApplicationCache() async throws {
        let settings = makeHistoryTestSettings()
        settings.enableWebsitePreviews = true
        ClipboardWebsiteIconCache.configureDiskStoreForTesting(
            directory: TestStorageFactory.makePaths().storageDirectory
                .appendingPathComponent("WebsiteIcons", isDirectory: true)
        )
        let applicationIcon = makeTestImage(size: NSSize(width: 32, height: 32))
        let websiteIcon = makeTestImage(size: NSSize(width: 64, height: 64), color: .systemPurple)
        let applicationIconLoader = ClipboardApplicationIconLoader { _ in applicationIcon }
        let url = try XCTUnwrap(URL(string: "https://icon-policy.example/path"))
        let item = ClipboardItem(
            sourceAppBundlePath: "/Applications/Example.app",
            content: .link(
                LinkItemContent(
                    url: url,
                    originalText: url.absoluteString
                )
            )
        )
        _ = await applicationIconLoader.loadIcon(for: item)
        ClipboardWebsiteIconLoader.storeWebsiteIcon(websiteIcon, for: url)

        let leadingIcon = ClipboardItemIconLoader.cachedLeadingIcon(
            for: item,
            settings: settings,
            applicationIconLoader: applicationIconLoader
        )

        XCTAssertFalse(leadingIcon === applicationIcon)
        XCTAssertNotNil(leadingIcon)
        XCTAssertTrue(applicationIconLoader.cachedIcon(for: item) === applicationIcon)
    }
}

final class ClipboardLegacyApplicationIconCacheCleanerTests: XCTestCase {
    func testCleanupRemovesFlattenedApplicationIconCache() async throws {
        let directory = TestStorageFactory.makePaths().storageDirectory
            .appendingPathComponent("ApplicationIcons", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appendingPathComponent("legacy.png"))
        let cleaner = ClipboardLegacyApplicationIconCacheCleaner(directory: directory)

        await cleaner.removeLegacyCacheIfNeeded()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
}

private struct IconRepresentationDescriptor: Equatable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let pointSize: NSSize
}
