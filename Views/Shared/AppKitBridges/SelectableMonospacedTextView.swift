import AppKit
import SwiftUI

struct SelectableMonospacedTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let usesMonospacedFont: Bool

    func makeNSView(context: Context) -> MeasuringSelectableTextView {
        let textView = MeasuringSelectableTextView(frame: .zero)
        textView.configure(fontSize: fontSize, usesMonospacedFont: usesMonospacedFont)
        textView.setText(text)
        return textView
    }

    func updateNSView(_ nsView: MeasuringSelectableTextView, context: Context) {
        nsView.configure(fontSize: fontSize, usesMonospacedFont: usesMonospacedFont)
        nsView.setText(text)
    }
}

final class MeasuringSelectableTextView: NSTextView {
    override init(frame frameRect: NSRect) {
        let container = NSTextContainer(size: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        let layoutManager = NSLayoutManager()
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return super.intrinsicContentSize
        }

        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let height = ceil(usedRect.height + textContainerInset.height * 2)

        return NSSize(width: NSView.noIntrinsicMetric, height: max(1, height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidthIfNeeded()
    }

    func configure(fontSize: CGFloat, usesMonospacedFont: Bool) {
        font = usesMonospacedFont
            ? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : .systemFont(ofSize: fontSize, weight: .regular)
        textColor = .labelColor
        insertionPointColor = .labelColor
    }

    func setText(_ text: String) {
        guard string != text else { return }
        string = text
        invalidateMeasuredLayout()
    }

    private func updateContainerWidthIfNeeded() {
        guard let textContainer else { return }

        let availableWidth = max(0, bounds.width)
        guard abs(textContainer.containerSize.width - availableWidth) > 0.5 else { return }

        textContainer.containerSize = NSSize(
            width: availableWidth,
            height: .greatestFiniteMagnitude
        )
        invalidateMeasuredLayout()
    }

    private func invalidateMeasuredLayout() {
        guard let layoutManager, let textContainer else {
            invalidateIntrinsicContentSize()
            return
        }

        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        layoutManager.ensureLayout(for: textContainer)
        invalidateIntrinsicContentSize()
    }
}
