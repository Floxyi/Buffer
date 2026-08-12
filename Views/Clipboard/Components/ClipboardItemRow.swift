import AppKit
import SwiftUI

/// Single row displaying a clipboard item - optimized for smooth scrolling.
struct ClipboardItemRow: View {
    private let leadingVisualSize = CGFloat(28)
    private let appIconScale = CGFloat(1.16)

    let item: ClipboardItem
    let store: ClipboardStore
    let settings: SettingsManager
    let primaryLabelText: String
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let isHovered: Bool
    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?
    @State private var imageDimensionsText: String?

    init(
        item: ClipboardItem,
        store: ClipboardStore,
        settings: SettingsManager,
        primaryLabelText: String,
        isMultiSelected: Bool,
        joinsSelectionAbove: Bool,
        joinsSelectionBelow: Bool,
        selectionJoinOverlap: CGFloat,
        quickPasteNumber: Int?,
        isHovered: Bool
    ) {
        self.item = item
        self.store = store
        self.settings = settings
        self.primaryLabelText = primaryLabelText
        self.isMultiSelected = isMultiSelected
        self.joinsSelectionAbove = joinsSelectionAbove
        self.joinsSelectionBelow = joinsSelectionBelow
        self.selectionJoinOverlap = selectionJoinOverlap
        self.quickPasteNumber = quickPasteNumber
        self.isHovered = isHovered
        self._thumbnail = State(
            initialValue: ClipboardItemRowAssetLoader.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
        )
        self._sourceAppIcon = State(
            initialValue: ClipboardItemRowAssetLoader.cachedDisplaySourceApplicationIcon(
                for: item,
                settings: settings
            )
        )
        self._imageDimensionsText = State(
            initialValue: ClipboardItemRowAssetLoader.cachedImageDimensionsText(for: item)
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
            return "Image (\(imageDimensionsText))"
        }

        return primaryLabelText
    }

    private var displayedThumbnail: NSImage? {
        thumbnail
            ?? ClipboardItemRowAssetLoader.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
    }

    private var displayedSourceAppIcon: NSImage? {
        sourceAppIcon
    }

    private var assetLoadToken: String {
        "\(item.id.uuidString)-\(settings.enableWebsitePreviews)"
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
                sourceAppIcon: displayedSourceAppIcon,
                thumbnail: displayedThumbnail,
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
        .task(id: assetLoadToken) {
            if thumbnail == nil, ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
                thumbnail = ClipboardItemRowAssetLoader.cachedThumbnail(
                    for: item,
                    leadingVisualSize: leadingVisualSize
                )
            }

            if imageDimensionsText == nil, ClipboardItemTypeRegistry.supportsImageAssets(for: item) {
                imageDimensionsText = ClipboardItemRowAssetLoader.cachedImageDimensionsText(for: item)
            }

            if sourceAppIcon == nil {
                sourceAppIcon = ClipboardItemRowAssetLoader.cachedDisplaySourceApplicationIcon(
                    for: item,
                    settings: settings
                )
            }

            await Task.yield()

            guard !Task.isCancelled else { return }

            await loadAssetsIfNeeded()
        }
        .onChange(of: item.id) { _ in
            thumbnail = ClipboardItemRowAssetLoader.cachedThumbnail(
                for: item,
                leadingVisualSize: leadingVisualSize
            )
            sourceAppIcon = ClipboardItemRowAssetLoader.cachedDisplaySourceApplicationIcon(
                for: item,
                settings: settings
            )
            imageDimensionsText = ClipboardItemRowAssetLoader.cachedImageDimensionsText(for: item)
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
            let loadedThumbnail = await ClipboardItemRowAssetLoader.loadThumbnail(
                for: item,
                store: store,
                leadingVisualSize: leadingVisualSize
            )

            guard !Task.isCancelled else { return }

            thumbnail = loadedThumbnail

            let loadedDimensionsText = await ClipboardItemRowAssetLoader.loadImageDimensionsText(
                for: item,
                store: store
            )

            guard !Task.isCancelled else { return }

            imageDimensionsText = loadedDimensionsText
        }

        if sourceAppIcon == nil {
            let fallbackIcon = await ClipboardSourceApplicationIconLoader.loadLocalSourceApplicationIcon(
                for: item,
                settings: settings
            )
            guard !Task.isCancelled else { return }
            sourceAppIcon = fallbackIcon
        }

        if item.kind == .link, settings.enableWebsitePreviews {
            let websiteIcon = await ClipboardItemRowAssetLoader.loadSourceApplicationIcon(
                for: item,
                settings: settings
            )
            guard !Task.isCancelled else { return }
            if let websiteIcon {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    sourceAppIcon = websiteIcon
                }
            }
        }
    }
}
