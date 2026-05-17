import AppKit
import SwiftUI

struct ClipboardLeadingVisual: View {
    let item: ClipboardItem
    let sourceAppIcon: NSImage?
    let thumbnail: NSImage?
    let secondaryForegroundColor: Color
    let leadingVisualSize: CGFloat
    let appIconScale: CGFloat

    var body: some View {
        switch ClipboardItemTypeRegistry.leadingVisualStyle(for: item) {
        case .document:
            textVisual
        case .image:
            imageVisual
        case .colorSwatch(let colorValue):
            colorVisual(colorValue)
        case .link:
            linkVisual
        }
    }

    @ViewBuilder
    private var textVisual: some View {
        if let sourceAppIcon {
            Image(nsImage: sourceAppIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: leadingVisualSize, height: leadingVisualSize)
                .scaleEffect(appIconScale)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
            .overlay {
                Group {
                    if let sourceAppIcon {
                        Image(nsImage: sourceAppIcon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: leadingVisualSize - 10, height: leadingVisualSize - 10)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor.opacity(0.9))
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
            )
            .help(item.linkPayload?.websiteName ?? "Website")
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
