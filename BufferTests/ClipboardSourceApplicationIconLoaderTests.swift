import XCTest
@testable import Buffer

@MainActor
final class ClipboardSourceApplicationIconLoaderTests: XCTestCase {
    func testSourceIconCacheKeyPrefersBundlePath() {
        let item = ClipboardItem(
            sourceAppBundleIdentifier: "com.example.app",
            sourceAppBundlePath: "/Applications/Example.app",
            content: .text(TextItemContent(inlineText: "hello"))
        )

        XCTAssertEqual(
            ClipboardSourceApplicationIconLoader.sourceIconCacheKey(for: item),
            "path:/Applications/Example.app"
        )
    }

    func testSourceIconCacheKeyFallsBackToBundleIdentifier() {
        let item = ClipboardItem(
            sourceAppBundleIdentifier: "com.example.app",
            content: .text(TextItemContent(inlineText: "hello"))
        )

        XCTAssertEqual(
            ClipboardSourceApplicationIconLoader.sourceIconCacheKey(for: item),
            "bundle:com.example.app"
        )
    }

    func testWebsiteIconCacheKeyUsesLowercasedHost() {
        let item = ClipboardItem.link(URL(string: "https://WWW.Example.COM/path")!, originalText: "https://WWW.Example.COM/path")

        XCTAssertEqual(
            ClipboardSourceApplicationIconLoader.websiteIconCacheKey(for: item),
            "website:www.example.com"
        )
    }
}
