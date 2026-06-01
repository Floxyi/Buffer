import AppKit
import XCTest

@testable import Buffer

@MainActor
final class ClipboardWebsiteIconCacheTests: XCTestCase {
    func testStoreNormalizesHostCaseAndClearsMissingMarker() throws {
        ClipboardWebsiteIconCache.clear()
        let lowercasedURL = try XCTUnwrap(URL(string: "https://openai.com/path"))
        let uppercasedURL = try XCTUnwrap(URL(string: "https://OPENAI.com/other"))

        ClipboardWebsiteIconCache.markMissing(for: lowercasedURL)
        XCTAssertTrue(ClipboardWebsiteIconCache.hasMarkedMissingIcon(for: uppercasedURL))

        ClipboardWebsiteIconCache.store(makeTestImage(size: NSSize(width: 32, height: 32)), for: lowercasedURL)

        XCTAssertNotNil(ClipboardWebsiteIconCache.cachedIcon(for: uppercasedURL))
        XCTAssertFalse(ClipboardWebsiteIconCache.hasMarkedMissingIcon(for: uppercasedURL))
    }

    func testStoreScalesOversizedIconsToPreferredMaximum() throws {
        ClipboardWebsiteIconCache.clear()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let image = makeTestImage(size: NSSize(width: 256, height: 128))

        ClipboardWebsiteIconCache.store(image, for: url)

        let cached = try XCTUnwrap(ClipboardWebsiteIconCache.cachedIcon(for: url))
        XCTAssertEqual(cached.size.width, 128, accuracy: 0.5)
        XCTAssertEqual(cached.size.height, 64, accuracy: 0.5)
    }

    func testClearRemovesCachedIconsAndMissingMarkers() throws {
        ClipboardWebsiteIconCache.clear()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        ClipboardWebsiteIconCache.store(makeTestImage(), for: url)
        ClipboardWebsiteIconCache.markMissing(for: url)

        ClipboardWebsiteIconCache.clear()

        XCTAssertNil(ClipboardWebsiteIconCache.cachedIcon(for: url))
        XCTAssertFalse(ClipboardWebsiteIconCache.hasMarkedMissingIcon(for: url))
    }
}
