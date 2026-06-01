import XCTest
@testable import Buffer

final class ClipboardColorValueTests: XCTestCase {
    func testParseSupportsHexRGBAndHSLVariants() throws {
        XCTAssertEqual(
            ClipboardColorValue.parse("#f0a"),
            ClipboardColorValue(red: 1, green: 0, blue: 170.0 / 255.0, alpha: 1)
        )
        XCTAssertEqual(
            ClipboardColorValue.parse("rgba(255, 0, 128, 0.5)"),
            ClipboardColorValue(red: 1, green: 0, blue: 128.0 / 255.0, alpha: 0.5)
        )
        let hslColor = try XCTUnwrap(ClipboardColorValue.parse("hsl(330, 100%, 50%)"))
        XCTAssertEqual(hslColor.red, 1, accuracy: 0.000_001)
        XCTAssertEqual(hslColor.green, 0, accuracy: 0.000_001)
        XCTAssertEqual(hslColor.blue, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(hslColor.alpha, 1, accuracy: 0.000_001)
    }

    func testParseRejectsMalformedColorText() {
        XCTAssertNil(ClipboardColorValue.parse("#12"))
        XCTAssertNil(ClipboardColorValue.parse("rgb(red, green, blue)"))
        XCTAssertNil(ClipboardColorValue.parse("hsl(10, 20, 30)"))
        XCTAssertNil(ClipboardColorValue.parse("not-a-color"))
    }

    func testFallbackUsesBlackForUnparseableText() {
        XCTAssertEqual(
            ClipboardColorValue.fallback(from: "nope"),
            ClipboardColorValue(red: 0, green: 0, blue: 0, alpha: 1)
        )
    }
}
