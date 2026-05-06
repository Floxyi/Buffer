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
        switch item.type {
        case .text:
            textVisual
        case .image:
            imageVisual
        }
    }

    @ViewBuilder
    private var textVisual: some View {
        if let content = item.textContent?.trimmingCharacters(in: .whitespaces),
           let color = ClipboardColorParser.parseColor(content) {
            Circle()
                .fill(color)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )
        } else if let sourceAppIcon {
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
