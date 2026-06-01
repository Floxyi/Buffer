import XCTest
@testable import Buffer

final class ClipboardLinkValueTests: XCTestCase {
    func testParseExplicitNormalizesSupportedWebURLs() {
        XCTAssertEqual(
            ClipboardLinkValue.parseExplicit("https://openai.com/docs")?.absoluteString,
            "https://openai.com/docs"
        )
        XCTAssertEqual(
            ClipboardLinkValue.parseExplicit("http://example.com/path?q=1")?.absoluteString,
            "http://example.com/path?q=1"
        )
        XCTAssertNil(ClipboardLinkValue.parseExplicit("ftp://example.com/file"))
        XCTAssertNil(ClipboardLinkValue.parseExplicit("two words"))
    }

    func testParseExplicitCanRequireHTTPS() {
        XCTAssertNil(ClipboardLinkValue.parseExplicit("http://openai.com", requiringHTTPS: true))
        XCTAssertEqual(
            ClipboardLinkValue.parseExplicit("https://openai.com", requiringHTTPS: true)?.absoluteString,
            "https://openai.com"
        )
    }

    func testParseImplicitWebsiteCandidateAddsHTTPS() {
        XCTAssertEqual(
            ClipboardLinkValue.parseImplicitWebsiteCandidate("openai.com/help")?.absoluteString,
            "https://openai.com/help"
        )
        XCTAssertNil(ClipboardLinkValue.parseImplicitWebsiteCandidate("https://openai.com"))
        XCTAssertNil(ClipboardLinkValue.parseImplicitWebsiteCandidate("localhost"))
    }

    func testWebsiteNameUsesRegistrableLabelAndHumanizesSegments() {
        XCTAssertEqual(
            ClipboardLinkValue.websiteName(for: URL(string: "https://www.openai.com/research")!),
            "Openai"
        )
        XCTAssertEqual(
            ClipboardLinkValue.websiteName(for: URL(string: "https://checkout.dodo-payments.co.uk")!),
            "Dodo Payments"
        )
    }
}
