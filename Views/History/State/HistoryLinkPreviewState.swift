@preconcurrency import LinkPresentation
import Foundation

struct HistoryLinkPreviewState {
    var metadata: LPLinkMetadata?
    var isLoadingMetadata = false
    var requestedURL: URL?

    func displayTitle(for linkPayload: LinkItemContent) -> String {
        let metadataTitle = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataTitle, !metadataTitle.isEmpty {
            return metadataTitle
        }

        return linkPayload.websiteName
    }

    func statusText(previewsEnabled: Bool) -> String {
        if !previewsEnabled {
            return "Website previews disabled"
        }

        return isLoadingMetadata ? "Loading preview…" : "Preview unavailable"
    }
}
