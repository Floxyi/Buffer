@preconcurrency import LinkPresentation
import SwiftUI

struct HistoryLinkDetailContent: View {
    let item: ClipboardItem
    let enableWebsitePreviews: Bool

    @State private var metadata: LPLinkMetadata?
    @State private var isLoadingMetadata = false
    @State private var requestedURL: URL?

    var body: some View {
        if let linkPayload = item.linkPayload {
            VStack(alignment: .leading, spacing: 12) {
                HistoryLinkPreviewCard {
                    Group {
                        if let metadata {
                            HistoryLinkPreviewView(metadata: metadata)
                                .clipped()
                        } else {
                            HistoryLinkFallbackCard(
                                websiteName: linkPayload.websiteName,
                                displayURL: linkPayload.displayURL,
                                icon: LinkPreviewAssetCache.cachedWebsiteIcon(for: linkPayload.url),
                                isLoadingMetadata: isLoadingMetadata,
                                previewsEnabled: enableWebsitePreviews
                            )
                        }
                    }
                    .id(linkPayload.displayURL)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle(for: linkPayload))
                        .font(.system(size: 13, weight: .medium))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(linkPayload.displayURL)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .task(id: linkPayload.displayURL) {
                await loadMetadataState(for: linkPayload.url)
            }
        }
    }

    @MainActor
    private func loadMetadataState(for url: URL) async {
        requestedURL = url
        metadata = nil

        guard enableWebsitePreviews else {
            isLoadingMetadata = false
            return
        }

        isLoadingMetadata = true
        let loadedMetadata = await LinkPreviewAssetCache.metadata(for: url)

        guard !Task.isCancelled else { return }
        guard requestedURL == url else { return }

        metadata = loadedMetadata
        isLoadingMetadata = false
    }

    private func displayTitle(for linkPayload: LinkItemContent) -> String {
        let metadataTitle = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataTitle, !metadataTitle.isEmpty {
            return metadataTitle
        }

        return linkPayload.websiteName
    }
}

private struct HistoryLinkFallbackCard: View {
    let websiteName: String
    let displayURL: String
    let icon: NSImage?
    let isLoadingMetadata: Bool
    let previewsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                    .overlay {
                        if let icon {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.accentColor.opacity(0.9))
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(websiteName)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)

                    Text(displayURL)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if isLoadingMetadata {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
        .padding(20)
    }

    private var statusText: String {
        if !previewsEnabled {
            return "Website previews disabled"
        }

        return isLoadingMetadata ? "Loading preview…" : "Preview unavailable"
    }
}

private struct HistoryLinkPreviewCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280, maxHeight: .infinity)
    }
}

private struct HistoryLinkPreviewView: NSViewRepresentable {
    let metadata: LPLinkMetadata

    func makeNSView(context: Context) -> HistoryLinkPreviewContainerView {
        let view = HistoryLinkPreviewContainerView()
        view.update(metadata: metadata)
        return view
    }

    func updateNSView(_ nsView: HistoryLinkPreviewContainerView, context: Context) {
        nsView.update(metadata: metadata)
    }
}

private final class HistoryLinkPreviewContainerView: NSView {
    private var currentMetadataIdentifier: String?
    private var linkView: LPLinkView?

    func update(metadata: LPLinkMetadata) {
        let nextIdentifier = [
            metadata.originalURL?.absoluteString,
            metadata.url?.absoluteString,
            metadata.title
        ]
        .compactMap { $0 }
        .joined(separator: "|")

        guard currentMetadataIdentifier != nextIdentifier else { return }
        currentMetadataIdentifier = nextIdentifier

        linkView?.removeFromSuperview()

        let nextLinkView = LPLinkView(metadata: metadata)
        nextLinkView.translatesAutoresizingMaskIntoConstraints = false
        nextLinkView.autoresizingMask = [.width, .height]
        nextLinkView.setContentHuggingPriority(.defaultLow, for: .vertical)
        nextLinkView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(nextLinkView)

        NSLayoutConstraint.activate([
            nextLinkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            nextLinkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            nextLinkView.topAnchor.constraint(equalTo: topAnchor),
            nextLinkView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        linkView = nextLinkView
    }
}
