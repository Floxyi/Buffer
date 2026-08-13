import XCTest

@testable import Buffer

@MainActor
final class ClipboardWebsiteIconLoaderTests: XCTestCase {
    func testFaviconURLUsesOriginRoot() {
        let item = ClipboardItem.link(
            URL(string: "https://example.com/articles?id=1#section")!,
            originalText: "https://example.com/articles?id=1#section"
        )

        XCTAssertEqual(
            ClipboardWebsiteIconLoader.faviconURL(for: item)?.absoluteString,
            "https://example.com/favicon.ico"
        )
    }

    func testFaviconURLRejectsUnsupportedScheme() {
        XCTAssertNil(
            ClipboardWebsiteIconLoader.faviconURL(
                for: URL(string: "ftp://example.com/file")!
            )
        )
    }
}
