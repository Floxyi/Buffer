@preconcurrency import LinkPresentation
import Foundation

@MainActor
struct HistoryLinkPreviewStateController {
    typealias MetadataProvider = @MainActor (URL) async -> LPLinkMetadata?

    private let metadataProvider: MetadataProvider

    init(metadataProvider: @escaping MetadataProvider = { url in
        await ClipboardWebsiteIconLoader.metadata(for: url)
    }) {
        self.metadataProvider = metadataProvider
    }

    func makeLoadingState(for url: URL, previewsEnabled: Bool) -> HistoryLinkPreviewState {
        HistoryLinkPreviewState(
            metadata: nil,
            isLoadingMetadata: previewsEnabled,
            requestedURL: url
        )
    }

    func loadState(for url: URL, previewsEnabled: Bool) async -> HistoryLinkPreviewState {
        var state = makeLoadingState(for: url, previewsEnabled: previewsEnabled)

        guard previewsEnabled else {
            return state
        }

        state.metadata = await metadataProvider(url)
        state.isLoadingMetadata = false
        return state
    }
}
