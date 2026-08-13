@preconcurrency import LinkPresentation
import XCTest

@testable import Buffer

@MainActor
final class HistoryLinkPreviewStateControllerTests: XCTestCase {
    func testLoadStateReturnsDisabledStateWithoutFetchingMetadata() async {
        var didLoadMetadata = false
        let controller = HistoryLinkPreviewStateController { _ in
            didLoadMetadata = true
            return nil
        }

        let url = URL(string: "https://example.com")!
        let state = await controller.loadState(for: url, previewsEnabled: false)

        XCTAssertFalse(didLoadMetadata)
        XCTAssertEqual(state.requestedURL, url)
        XCTAssertFalse(state.isLoadingMetadata)
        XCTAssertNil(state.metadata)
        XCTAssertEqual(state.statusText(previewsEnabled: false), "Website previews disabled")
    }

    func testLoadStateLoadsMetadataWhenPreviewsEnabled() async {
        let metadata = LPLinkMetadata()
        metadata.title = "Example"

        let controller = HistoryLinkPreviewStateController { _ in
            metadata
        }

        let url = URL(string: "https://example.com")!
        let state = await controller.loadState(for: url, previewsEnabled: true)

        XCTAssertEqual(state.requestedURL, url)
        XCTAssertFalse(state.isLoadingMetadata)
        XCTAssertEqual(state.metadata?.title, "Example")
        XCTAssertEqual(state.statusText(previewsEnabled: true), "Preview unavailable")
    }
}
