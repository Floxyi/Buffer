@preconcurrency import LinkPresentation
import SwiftUI

struct HistoryLinkDetailContent: View {
    let item: ClipboardItem
    let enableWebsitePreviews: Bool

    @State private var previewState = HistoryLinkPreviewState()

    private let previewStateController = HistoryLinkPreviewStateController()

    var body: some View {
        if let linkPayload = item.linkPayload {
            VStack(alignment: .leading, spacing: 12) {
                HistoryLinkPreviewCard {
                    Group {
                        if let metadata = previewState.metadata {
                            HistoryLinkPreviewView(metadata: metadata)
                                .clipped()
                        } else {
                            HistoryLinkFallbackCard(
                                websiteName: linkPayload.websiteName,
                                displayURL: linkPayload.displayURL,
                                icon: ClipboardWebsiteIconLoader.cachedWebsiteIcon(for: linkPayload.url),
                                statusText: previewState.statusText(previewsEnabled: enableWebsitePreviews),
                                isLoadingMetadata: previewState.isLoadingMetadata
                            )
                        }
                    }
                    .id(linkPayload.displayURL)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 8) {
                    Text(previewState.displayTitle(for: linkPayload))
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
        previewState = previewStateController.makeLoadingState(
            for: url,
            previewsEnabled: enableWebsitePreviews
        )
        let loadedState = await previewStateController.loadState(
            for: url,
            previewsEnabled: enableWebsitePreviews
        )

        guard !Task.isCancelled else { return }
        guard previewState.requestedURL == url else { return }
        previewState = loadedState
    }
}

private struct HistoryLinkFallbackCard: View {
    let websiteName: String
    let displayURL: String
    let icon: NSImage?
    let statusText: String
    let isLoadingMetadata: Bool

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
