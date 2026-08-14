import AppKit
import SwiftUI

struct ClipboardLeadingVisual: View {
    let item: ClipboardItem
    let leadingIcon: NSImage?
    let leadingIconUsesApplicationAppearance: Bool
    let thumbnail: NSImage?
    let secondaryForegroundColor: Color
    let leadingVisualSize: CGFloat

    var body: some View {
        Group {
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
        .frame(width: leadingVisualSize, height: leadingVisualSize)
    }

    @ViewBuilder
    private var textVisual: some View {
        if item.sourceApp != nil || item.sourceAppBundleIdentifier != nil || item.sourceAppBundlePath != nil {
            ClipboardApplicationIconView(
                item: item,
                size: leadingVisualSize,
                fallbackIcon: leadingIcon,
                contentScale: 1.18
            )
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
                        linkIcon(leadingIcon, size: leadingVisualSize)
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

                        linkIcon(leadingIcon, size: leadingVisualSize - 10)
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
    private func linkIcon(_ icon: NSImage, size: CGFloat) -> some View {
        if leadingIconUsesApplicationAppearance {
            ClipboardApplicationIconView(
                item: item,
                size: size,
                fallbackIcon: icon,
                contentScale: 1.18
            )
        } else {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
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

struct ClipboardApplicationIconView: View {
    let item: ClipboardItem
    let size: CGFloat
    var fallbackIcon: NSImage?
    var contentScale = CGFloat(1)

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var iconLoader = ClipboardApplicationIconLoader.shared
    @State private var icon: NSImage?
    @State private var loadedAppearance: ClipboardApplicationIconAppearance?

    private var appearance: ClipboardApplicationIconAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var loadToken: String {
        "\(item.id.uuidString)-\(appearance.rawValue)-\(iconLoader.iconRevision)"
    }

    var body: some View {
        let cachedIcon = iconLoader.cachedIcon(
            for: item,
            appearance: appearance
        )

        Group {
            if let cachedIcon {
                applicationImage(cachedIcon)
            } else if loadedAppearance == appearance, let icon {
                applicationImage(icon)
            } else if let fallbackIcon {
                applicationImage(fallbackIcon)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: max(8, size * 0.58)))
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(contentScale)
        .frame(width: size, height: size)
        .clipped()
        .task(id: loadToken) {
            let revision = iconLoader.iconRevision
            if let cachedIcon = iconLoader.cachedIcon(for: item, appearance: appearance) {
                icon = cachedIcon
                loadedAppearance = appearance
                return
            }

            let loadedIcon = await iconLoader.loadIcon(for: item, appearance: appearance)
            guard !Task.isCancelled, iconLoader.iconRevision == revision else { return }
            icon = loadedIcon
            loadedAppearance = appearance
        }
    }

    private func applicationImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}
