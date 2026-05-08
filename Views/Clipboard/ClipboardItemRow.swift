import SwiftUI
import AppKit

/// Single row displaying a clipboard item - optimized for smooth scrolling.
struct ClipboardItemRow: View {
    private let leadingVisualSize = CGFloat(28)
    private let appIconScale = CGFloat(1.16)

    let item: ClipboardItem
    let store: ClipboardStore
    let primaryLabelText: String
    let scrollActivityTracker: ScrollActivityTracker
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let selectionJoinOverlap: CGFloat
    let quickPasteNumber: Int?
    let isHovered: Bool

    @State private var thumbnail: NSImage?
    @State private var sourceAppIcon: NSImage?
    @State private var imageDimensionsText: String?

    @ObservedObject private var observedScrollActivityTracker: ScrollActivityTracker

    init(
        item: ClipboardItem,
        store: ClipboardStore,
        primaryLabelText: String,
        scrollActivityTracker: ScrollActivityTracker,
        isMultiSelected: Bool,
        joinsSelectionAbove: Bool,
        joinsSelectionBelow: Bool,
        selectionJoinOverlap: CGFloat,
        quickPasteNumber: Int?,
        isHovered: Bool
    ) {
        self.item = item
        self.store = store
        self.primaryLabelText = primaryLabelText
        self.scrollActivityTracker = scrollActivityTracker
        self.isMultiSelected = isMultiSelected
        self.joinsSelectionAbove = joinsSelectionAbove
        self.joinsSelectionBelow = joinsSelectionBelow
        self.selectionJoinOverlap = selectionJoinOverlap
        self.quickPasteNumber = quickPasteNumber
        self.isHovered = isHovered
        self._observedScrollActivityTracker = ObservedObject(wrappedValue: scrollActivityTracker)
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
        guard item.type == .image else {
            return primaryLabelText
        }

        if let imageDimensionsText {
            return "Image (\(imageDimensionsText))"
        }

        return primaryLabelText
    }

    private var assetLoadToken: String {
        "\(item.id.uuidString)-\(observedScrollActivityTracker.isScrolling)"
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
            guard !observedScrollActivityTracker.isScrolling else { return }

            try? await Task.sleep(nanoseconds: 25_000_000)

            guard !Task.isCancelled else { return }
            guard !observedScrollActivityTracker.isScrolling else { return }

            await loadAssetsIfNeeded()
        }
        .onChange(of: item.id) { _ in
            thumbnail = nil
            sourceAppIcon = nil
            imageDimensionsText = nil
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
        guard !observedScrollActivityTracker.isScrolling else { return }

        if item.type == .image && thumbnail == nil {
            let loadedThumbnail = await ClipboardItemRowAssetLoader.loadThumbnail(
                for: item,
                store: store,
                leadingVisualSize: leadingVisualSize
            )

            guard !Task.isCancelled else { return }
            guard !observedScrollActivityTracker.isScrolling else { return }

            thumbnail = loadedThumbnail

            let loadedDimensionsText = await ClipboardItemRowAssetLoader.loadImageDimensionsText(
                for: item,
                store: store
            )

            guard !Task.isCancelled else { return }
            guard !observedScrollActivityTracker.isScrolling else { return }

            imageDimensionsText = loadedDimensionsText
        }

        guard !observedScrollActivityTracker.isScrolling else { return }

        if sourceAppIcon == nil {
            let loadedSourceAppIcon = await ClipboardItemRowAssetLoader.loadSourceApplicationIcon(for: item)

            guard !Task.isCancelled else { return }
            guard !observedScrollActivityTracker.isScrolling else { return }

            sourceAppIcon = loadedSourceAppIcon
        }
    }
}
