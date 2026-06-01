import XCTest
@testable import Buffer

@MainActor
final class ClipboardCaptureClassificationTests: XCTestCase {
    func testColorClassificationCreatesStructuredColorItem() async {
        let item = await ClipboardCaptureSupport.classifyTextItem(
            "#ff0000",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }

        XCTAssertEqual(item.kind, .color)
        XCTAssertEqual(item.colorPayload?.originalText, "#ff0000")
        XCTAssertEqual(item.textContent, nil)
    }

    func testColorClassificationRecognizesRGBAndHSL() async {
        let rgbItem = await ClipboardCaptureSupport.classifyTextItem(
            "rgba(255, 0, 128, 0.5)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }
        let hslItem = await ClipboardCaptureSupport.classifyTextItem(
            "hsl(330, 100%, 50%)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline color item")
            return nil
        }

        XCTAssertEqual(rgbItem.kind, .color)
        XCTAssertEqual(
            rgbItem.colorPayload?.value,
            ClipboardColorValue(red: 1, green: 0, blue: 128.0 / 255.0, alpha: 0.5)
        )
        XCTAssertEqual(hslItem.kind, .color)
        XCTAssertEqual(hslItem.colorPayload?.originalText, "hsl(330, 100%, 50%)")
    }

    func testColorClassificationRejectsNonColorHashText() async {
        let headingItem = await ClipboardCaptureSupport.classifyTextItem(
            "## Phase 1: Polish",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let malformedHexItem = await ClipboardCaptureSupport.classifyTextItem(
            "#12 nope",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let malformedRGBItem = await ClipboardCaptureSupport.classifyTextItem(
            "rgb(255, blue, 0)",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(headingItem.kind, .text)
        XCTAssertEqual(headingItem.textContent, "## Phase 1: Polish")
        XCTAssertNil(headingItem.colorPayload)
        XCTAssertEqual(malformedHexItem.kind, .text)
        XCTAssertNil(malformedHexItem.colorPayload)
        XCTAssertEqual(malformedRGBItem.kind, .text)
        XCTAssertNil(malformedRGBItem.colorPayload)
    }

    func testLinkClassificationCreatesStructuredLinkItem() async {
        let httpsItem = await ClipboardCaptureSupport.classifyTextItem(
            "https://www.youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }
        let schemeLessItem = await ClipboardCaptureSupport.classifyTextItem(
            "openai.com/research",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in true }
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        XCTAssertEqual(httpsItem.kind, .link)
        XCTAssertEqual(httpsItem.linkPayload?.websiteName, "Youtube")
        XCTAssertEqual(httpsItem.linkPayload?.originalText, "https://www.youtube.com/watch?v=123")
        XCTAssertEqual(schemeLessItem.kind, .link)
        XCTAssertEqual(schemeLessItem.linkPayload?.url.absoluteString, "https://openai.com/research")
    }

    func testLinkClassificationRejectsNonURLText() async {
        let plainTextItem = await ClipboardCaptureSupport.classifyTextItem(
            "openai research",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let markdownHeadingItem = await ClipboardCaptureSupport.classifyTextItem(
            "# Release Notes",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }
        let nonWebSchemeItem = await ClipboardCaptureSupport.classifyTextItem(
            "file:///tmp/test.txt",
            sourceApp: nil,
            enableWebsitePreviews: true
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(plainTextItem.kind, .text)
        XCTAssertNil(plainTextItem.linkPayload)
        XCTAssertEqual(markdownHeadingItem.kind, .text)
        XCTAssertNil(markdownHeadingItem.linkPayload)
        XCTAssertEqual(nonWebSchemeItem.kind, .text)
        XCTAssertNil(nonWebSchemeItem.linkPayload)
    }

    func testImplicitLinkClassificationRequiresReachableWebsite() async {
        let reachableItem = await ClipboardCaptureSupport.classifyTextItem(
            "youtube.com",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in true }
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        let unreachableItem = await ClipboardCaptureSupport.classifyTextItem(
            "bla.bla",
            sourceApp: nil,
            enableWebsitePreviews: true,
            websiteReachability: { _ in false }
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(reachableItem.kind, .link)
        XCTAssertEqual(reachableItem.linkPayload?.url.absoluteString, "https://youtube.com")
        XCTAssertEqual(unreachableItem.kind, .text)
        XCTAssertNil(unreachableItem.linkPayload)
    }

    func testLocalOnlyModeRequiresExplicitHTTPSLinks() async {
        let httpsItem = await ClipboardCaptureSupport.classifyTextItem(
            "https://youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline link item")
            return nil
        }

        let httpItem = await ClipboardCaptureSupport.classifyTextItem(
            "http://youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        let schemeLessItem = await ClipboardCaptureSupport.classifyTextItem(
            "youtube.com/watch?v=123",
            sourceApp: nil,
            enableWebsitePreviews: false
        ) { _ in
            XCTFail("Expected inline plain text item")
            return nil
        }

        XCTAssertEqual(httpsItem.kind, .link)
        XCTAssertEqual(httpItem.kind, .text)
        XCTAssertEqual(schemeLessItem.kind, .text)
    }
}
