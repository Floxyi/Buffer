import SwiftUI
import AppKit

/// Single row displaying a clipboard item - optimized for smooth scrolling.
struct ClipboardItemRow: View {
    private let leadingVisualSize = CGFloat(28)
    private let appIconScale = CGFloat(1.16)

    let item: ClipboardItem
    let primaryLabelText: String
    let assets: ClipboardItemRowAssets
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let isHovered: Bool

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

    private var displayedPrimaryLabelText: String {
        guard item.type == .image else {
            return primaryLabelText
        }

        if let imageDimensionsText = assets.imageDimensionsText {
            return "Image (\(imageDimensionsText))"
        }

        return primaryLabelText
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
                sourceAppIcon: assets.sourceAppIcon,
                thumbnail: assets.thumbnail,
                secondaryForegroundColor: secondaryForegroundColor,
                leadingVisualSize: leadingVisualSize,
                appIconScale: appIconScale
            )
            .frame(width: leadingVisualSize, height: leadingVisualSize)

            Text(displayedPrimaryLabelText)
                .font(.system(size: 13))
                .foregroundColor(foregroundColor)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: ClipboardListStructure.LayoutMetrics.itemRowHeight)
        .background(selectionBackground)
        .transaction { transaction in
            transaction.animation = nil
        }
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
