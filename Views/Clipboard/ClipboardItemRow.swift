import SwiftUI
import AppKit

/// Single row displaying a clipboard item - optimized for smooth scrolling.
struct ClipboardItemRow: View {
    private let leadingVisualSize = CGFloat(28)
    private let appIconScale = CGFloat(1.16)

    let item: ClipboardItem
    let store: ClipboardStore
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let isHovered: Bool

    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?
    @State private var imageDimensionsText: String?

    private var backgroundColor: Color {
        if isMultiSelected {
            return Color(nsColor: .selectedContentBackgroundColor)
        } else if isHovered {
            return Color(nsColor: .secondaryLabelColor).opacity(0.12)
        }
        return Color.clear
    }

    private var foregroundColor: Color {
        isMultiSelected ? Color(nsColor: .selectedTextColor) : .primary
    }

    private var secondaryForegroundColor: Color {
        isMultiSelected ? Color(nsColor: .selectedTextColor).opacity(0.82) : .secondary
    }

    private var selectionCornerRadius: CGFloat { 6 }

    private var primaryLabelText: String {
        switch item.type {
        case .text:
            let text = item.textContent ?? item.previewText
            let singleLine = text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if singleLine.count > 50 {
                return String(singleLine.prefix(50)) + "…"
            }

            return singleLine

        case .image:
            if let imageDimensionsText {
                return "Image (\(imageDimensionsText))"
            }

            return "Image"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let quickPasteNumber {
                ClipboardQuickPasteBadge(
                    number: quickPasteNumber,
                    foregroundColor: foregroundColor,
                    isMultiSelected: isMultiSelected
                )
                .transition(
                    .asymmetric(
                        insertion: .offset(x: -10).combined(with: .opacity),
                        removal: .offset(x: -10).combined(with: .opacity)
                    )
                )
            }

            ClipboardLeadingVisual(
                item: item,
                sourceAppIcon: sourceAppIcon,
                thumbnail: thumbnail,
                secondaryForegroundColor: secondaryForegroundColor,
                leadingVisualSize: leadingVisualSize,
                appIconScale: appIconScale
            )
            .frame(width: leadingVisualSize, height: leadingVisualSize)

            Text(primaryLabelText)
                .font(.system(size: 13))
                .foregroundColor(foregroundColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(selectionBackground)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .task(id: item.id) {
            if item.type == .image && thumbnail == nil {
                thumbnail = await ClipboardItemRowAssetLoader.loadThumbnail(
                    for: item,
                    store: store,
                    leadingVisualSize: leadingVisualSize
                )

                imageDimensionsText = await ClipboardItemRowAssetLoader.loadImageDimensionsText(
                    for: item,
                    store: store
                )
            }

            if sourceAppIcon == nil {
                sourceAppIcon = await ClipboardItemRowAssetLoader.loadSourceApplicationIcon(for: item)
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.9), value: quickPasteNumber != nil)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        ClipboardRowSelectionBackground(
            isMultiSelected: isMultiSelected,
            joinsSelectionAbove: joinsSelectionAbove,
            joinsSelectionBelow: joinsSelectionBelow,
            backgroundColor: backgroundColor,
            selectionCornerRadius: selectionCornerRadius,
            selectionJoinOverlap: selectionJoinOverlap
        )
    }
}
