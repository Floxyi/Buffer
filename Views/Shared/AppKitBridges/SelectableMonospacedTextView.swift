import AppKit
import SwiftUI

struct SelectableMonospacedTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let usesMonospacedFont: Bool
    let showsSpacesAndTabs: Bool

    init(
        text: String,
        fontSize: CGFloat,
        usesMonospacedFont: Bool,
        showsSpacesAndTabs: Bool = false
    ) {
        self.text = text
        self.fontSize = fontSize
        self.usesMonospacedFont = usesMonospacedFont
        self.showsSpacesAndTabs = showsSpacesAndTabs
    }

    func makeNSView(context: Context) -> MeasuringSelectableTextView {
        let textView = MeasuringSelectableTextView(frame: .zero)
        textView.configure(fontSize: fontSize, usesMonospacedFont: usesMonospacedFont)
        textView.setShowsSpacesAndTabs(showsSpacesAndTabs)
        textView.setText(text)
        return textView
    }

    func updateNSView(_ nsView: MeasuringSelectableTextView, context: Context) {
        nsView.configure(fontSize: fontSize, usesMonospacedFont: usesMonospacedFont)
        nsView.setShowsSpacesAndTabs(showsSpacesAndTabs)
        nsView.setText(text)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MeasuringSelectableTextView,
        context: Context
    ) -> CGSize? {
        guard let proposedWidth = proposal.width,
              proposedWidth.isFinite,
              proposedWidth > 0 else {
            return nil
        }

        return CGSize(
            width: proposedWidth,
            height: nsView.measuredHeight(constrainedTo: proposedWidth)
        )
    }
}

final class MeasuringSelectableTextView: NSTextView {
    private static let geometryTolerance = CGFloat(0.5)

    override init(frame frameRect: NSRect) {
        let container = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        let layoutManager = WhitespaceVisualizingLayoutManager()
        layoutManager.addTextContainer(container)
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)

        super.init(frame: frameRect, textContainer: container)

        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        autoresizingMask = [.width]
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let containerWidth = textContainer?.containerSize.width ?? 0
        let measurementWidth = containerWidth > 0 ? containerWidth : bounds.width
        guard measurementWidth.isFinite, measurementWidth > 0 else {
            return super.intrinsicContentSize
        }

        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: measuredHeight(constrainedTo: measurementWidth)
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(frame.width - newSize.width) > Self.geometryTolerance
        super.setFrameSize(newSize)

        guard widthChanged else { return }
        updateContainerWidth(newSize.width)
        invalidateMeasuredLayout()
    }

    func configure(fontSize: CGFloat, usesMonospacedFont: Bool) {
        let configuredFont: NSFont = usesMonospacedFont
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize, weight: .regular)

        if font != configuredFont {
            font = configuredFont
            invalidateMeasuredLayout()
        }

        textColor = .labelColor
        insertionPointColor = .labelColor
    }

    func setText(_ text: String) {
        guard string != text else { return }
        string = text
        invalidateMeasuredLayout()
    }

    func setShowsSpacesAndTabs(_ isVisible: Bool) {
        guard let layoutManager = layoutManager as? WhitespaceVisualizingLayoutManager else {
            return
        }
        layoutManager.showsSpacesAndTabs = isVisible
    }

    func measuredHeight(constrainedTo proposedWidth: CGFloat) -> CGFloat {
        let width = max(1, proposedWidth)
        updateContainerWidth(width)

        guard let layoutManager, let textContainer else { return 1 }

        layoutManager.ensureLayout(for: textContainer)

        var contentMaxY = layoutManager.usedRect(for: textContainer).maxY
        if layoutManager.extraLineFragmentTextContainer === textContainer {
            contentMaxY = max(contentMaxY, layoutManager.extraLineFragmentRect.maxY)
        }

        return max(1, ceil(contentMaxY + textContainerInset.height * 2))
    }

    private func updateContainerWidth(_ proposedWidth: CGFloat) {
        guard let textContainer else { return }

        let width = max(1, proposedWidth)
        guard abs(textContainer.containerSize.width - width) > Self.geometryTolerance else {
            return
        }

        textContainer.containerSize = NSSize(
            width: width,
            height: .greatestFiniteMagnitude
        )
    }

    private func invalidateMeasuredLayout() {
        guard let layoutManager else {
            invalidateIntrinsicContentSize()
            return
        }

        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        invalidateIntrinsicContentSize()
    }
}

final class WhitespaceVisualizingLayoutManager: NSLayoutManager {
    private static let space = unichar(0x20)
    private static let tab = unichar(0x09)

    var showsSpacesAndTabs = false {
        didSet {
            guard showsSpacesAndTabs != oldValue else { return }
            invalidateDisplay(forCharacterRange: fullCharacterRange)
        }
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard showsSpacesAndTabs,
              let textStorage,
              let textContainer = textContainers.first,
              glyphsToShow.length > 0 else {
            return
        }

        let characterRange = characterRange(
            forGlyphRange: glyphsToShow,
            actualGlyphRange: nil
        )
        let string = textStorage.string as NSString
        let upperBound = min(NSMaxRange(characterRange), string.length)

        for characterIndex in characterRange.location..<upperBound {
            let character = string.character(at: characterIndex)
            guard let marker = Self.marker(for: character) else { continue }

            let characterGlyphRange = glyphRange(
                forCharacterRange: NSRange(location: characterIndex, length: 1),
                actualCharacterRange: nil
            )
            guard characterGlyphRange.length > 0,
                  NSIntersectionRange(characterGlyphRange, glyphsToShow).length > 0 else {
                continue
            }

            drawMarker(
                marker,
                scale: Self.markerScale(for: character),
                forCharacterAt: characterIndex,
                glyphRange: characterGlyphRange,
                textStorage: textStorage,
                textContainer: textContainer,
                origin: origin
            )
        }
    }

    static func marker(for character: unichar) -> String? {
        switch character {
        case space: return "·"
        case tab: return "→"
        default: return nil
        }
    }

    private static func markerScale(for character: unichar) -> CGFloat {
        character == space ? 0.92 : 0.78
    }

    private var fullCharacterRange: NSRange {
        NSRange(location: 0, length: textStorage?.length ?? 0)
    }

    private func drawMarker(
        _ marker: String,
        scale: CGFloat,
        forCharacterAt characterIndex: Int,
        glyphRange: NSRange,
        textStorage: NSTextStorage,
        textContainer: NSTextContainer,
        origin: NSPoint
    ) {
        let font = textStorage.attribute(
            .font,
            at: characterIndex,
            effectiveRange: nil
        ) as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)

        let markerFont = NSFont.systemFont(
            ofSize: max(7, font.pointSize * scale),
            weight: .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: markerFont,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.90)
        ]
        let markerSize = marker.size(withAttributes: attributes)
        let glyphBounds = boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let markerOrigin = NSPoint(
            x: origin.x + glyphBounds.midX - markerSize.width / 2,
            y: origin.y + glyphBounds.midY - markerSize.height / 2
        )

        marker.draw(at: markerOrigin, withAttributes: attributes)
    }
}
