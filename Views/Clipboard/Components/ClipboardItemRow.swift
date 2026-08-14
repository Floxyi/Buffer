import AppKit
import SwiftUI

/// Single row displaying a clipboard item - optimized for smooth scrolling.
struct ClipboardItemRow: View {
    private let leadingVisualSize = CGFloat(28)

    let item: ClipboardItem
    let websitePreviewsEnabled: Bool
    let primaryLabelText: String
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let queryPlan: ClipboardQueryPlan?
    let contentMatchClassification: ClipboardMatchClassification?
    let isHovered: Bool
    private let assetProvider: any ClipboardItemAssetProviding
    @State private var thumbnail: NSImage?
    @State private var leadingIcon: NSImage?
    @State private var imageDimensionsText: String?

    init(
        item: ClipboardItem,
        websitePreviewsEnabled: Bool,
        primaryLabelText: String,
        isMultiSelected: Bool,
        joinsSelectionAbove: Bool,
        joinsSelectionBelow: Bool,
        selectionJoinOverlap: CGFloat,
        quickPasteNumber: Int?,
        queryPlan: ClipboardQueryPlan? = nil,
        contentMatchClassification: ClipboardMatchClassification? = nil,
        isHovered: Bool,
        assetProvider: any ClipboardItemAssetProviding
    ) {
        self.item = item
        self.websitePreviewsEnabled = websitePreviewsEnabled
        self.primaryLabelText = primaryLabelText
        self.isMultiSelected = isMultiSelected
        self.joinsSelectionAbove = joinsSelectionAbove
        self.joinsSelectionBelow = joinsSelectionBelow
        self.selectionJoinOverlap = selectionJoinOverlap
        self.quickPasteNumber = quickPasteNumber
        self.queryPlan = queryPlan
        self.contentMatchClassification = contentMatchClassification
        self.isHovered = isHovered
        self.assetProvider = assetProvider
        self._thumbnail = State(
            initialValue: assetProvider.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
        )
        self._leadingIcon = State(
            initialValue: assetProvider.cachedLeadingIcon(for: item)
        )
        self._imageDimensionsText = State(
            initialValue: assetProvider.cachedImageDimensionsText(for: item)
        )
    }

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
        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item) else {
            return primaryLabelText
        }

        if let imageDimensionsText {
            return String(localized: "Image (\(imageDimensionsText))")
        }

        return primaryLabelText
    }

    private var displayedThumbnail: NSImage? {
        thumbnail
            ?? assetProvider.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
    }

    private var assetLoadToken: String {
        "\(item.id.uuidString)-\(websitePreviewsEnabled)"
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
                leadingIcon: leadingIcon,
                leadingIconUsesApplicationAppearance: item.kind == .text
                    || (item.kind == .link && !websitePreviewsEnabled),
                thumbnail: displayedThumbnail,
                secondaryForegroundColor: secondaryForegroundColor,
                leadingVisualSize: leadingVisualSize
            )
            .frame(width: leadingVisualSize, height: leadingVisualSize)

            ClipboardMatchedText(
                text: displayedPrimaryLabelText,
                queryPlan: queryPlan,
                matchClassification: contentMatchClassification
            )
            .font(.system(size: 13))
            .foregroundColor(foregroundColor)
            .lineLimit(1)

            if item.isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(secondaryForegroundColor)
                    .accessibilityLabel(String(localized: "Bookmarked"))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(height: ClipboardListStructure.LayoutMetrics.itemRowHeight)
        .background(selectionBackground)
        .transaction { transaction in
            transaction.animation = nil
        }
        .task(id: assetLoadToken) {
            if thumbnail == nil, ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
                thumbnail = assetProvider.cachedThumbnail(
                    for: item,
                    leadingVisualSize: leadingVisualSize
                )
            }

            if imageDimensionsText == nil, ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
                imageDimensionsText = assetProvider.cachedImageDimensionsText(for: item)
            }

            if leadingIcon == nil {
                leadingIcon = assetProvider.cachedLeadingIcon(for: item)
            }

            await Task.yield()

            guard !Task.isCancelled else { return }

            await loadAssetsIfNeeded()
        }
        .onChange(of: item.id) { _ in
            thumbnail = assetProvider.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
            leadingIcon = assetProvider.cachedLeadingIcon(for: item)
            imageDimensionsText = assetProvider.cachedImageDimensionsText(for: item)
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

    private func loadAssetsIfNeeded() async {
        if ClipboardItemTypeRegistry.supportsImageAssets(for: item), thumbnail == nil {
            let loadedThumbnail = await assetProvider.loadThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )

            guard !Task.isCancelled else { return }

            thumbnail = loadedThumbnail

            let loadedDimensionsText = await assetProvider.loadImageDimensionsText(for: item)

            guard !Task.isCancelled else { return }

            imageDimensionsText = loadedDimensionsText
        }

        if leadingIcon == nil, item.kind != .email {
            let fallbackIcon = await assetProvider.loadApplicationIcon(for: item)
            guard !Task.isCancelled else { return }
            leadingIcon = fallbackIcon
        }

        if item.kind == .link, websitePreviewsEnabled {
            let websiteIcon = await assetProvider.loadPreferredLeadingIcon(for: item)
            guard !Task.isCancelled else { return }
            if let websiteIcon {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    leadingIcon = websiteIcon
                }
            }
        }
    }
}
