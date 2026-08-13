import AppKit
import SwiftUI

struct ClipboardLeadingVisual: View {
    let item: ClipboardItem
    let leadingIcon: NSImage?
    let thumbnail: NSImage?
    let secondaryForegroundColor: Color
    let leadingVisualSize: CGFloat

    var body: some View {
        switch ClipboardItemPresentation.leadingVisualStyle(for: item) {
        case .document:
            textVisual
        case .image:
            imageVisual
        case .colorSwatch(let colorValue):
            colorVisual(colorValue)
        case .link:
            linkVisual
        case .email:
            emailVisual
        }
    }

    @ViewBuilder
    private var textVisual: some View {
        if let leadingIcon {
            Image(nsImage: leadingIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: leadingVisualSize, height: leadingVisualSize)
                .help(item.sourceApp ?? "Source App")
        } else if item.sourceApp != nil || item.sourceAppBundleIdentifier != nil || item.sourceAppBundlePath != nil {
            Image(systemName: "app.fill")
                .font(.system(size: 14))
                .foregroundColor(secondaryForegroundColor)
                .help(item.sourceApp ?? "Source App")
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 14))
                .foregroundColor(secondaryForegroundColor)
        }
    }

    private func colorVisual(_ colorValue: ClipboardColorValue) -> some View {
        Circle()
            .fill(Color(nsColor: colorValue.nsColor))
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }

    private var linkVisual: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        return
            shape
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.24),
                        Color.accentColor.opacity(0.14),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let leadingIcon {
                    ZStack {
                        Image(nsImage: leadingIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: leadingVisualSize, height: leadingVisualSize)
                            .scaleEffect(1.35)
                            .blur(radius: 10)
                            .opacity(0.5)

                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        Image(nsImage: leadingIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: leadingVisualSize - 10, height: leadingVisualSize - 10)
                            .shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 0.5)
                    }
                    .clipShape(shape)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.accentColor.opacity(0.9))
                }
            }
            .overlay(
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .help(item.linkPayload?.websiteName ?? "Website")
    }

    private var emailVisual: some View {
        Image(systemName: "envelope.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(secondaryForegroundColor)
            .help("Email")
    }

    @ViewBuilder
    private var imageVisual: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: leadingVisualSize, height: leadingVisualSize)
                .clipped()
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
        }
    }
}
