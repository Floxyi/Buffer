import AppKit
import SwiftUI

struct ScrollViewConfigurator: NSViewRepresentable {
    enum SearchStrategy {
        case nearestAncestorOnly
        case nearestOrFallback
    }

    let configure: (NSScrollView) -> Void
    var searchStrategy: SearchStrategy = .nearestOrFallback

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.configure = configure
        view.searchStrategy = searchStrategy
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.configure = configure
        nsView.searchStrategy = searchStrategy
        nsView.scheduleConfiguration()
    }

    final class ConfiguratorView: NSView {
        var configure: ((NSScrollView) -> Void)?
        var searchStrategy: SearchStrategy = .nearestOrFallback

        private var isConfigurationScheduled = false

        override var intrinsicContentSize: NSSize {
            NSSize(width: 0, height: 0)
        }

        override var fittingSize: NSSize {
            NSSize(width: 0, height: 0)
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            scheduleConfiguration()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleConfiguration()
        }

        func scheduleConfiguration() {
            guard !isConfigurationScheduled else { return }

            isConfigurationScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                self.isConfigurationScheduled = false
                self.applyConfigurationIfPossible()
            }
        }

        private func applyConfigurationIfPossible() {
            guard let scrollView = findScrollView() else {
                scheduleConfiguration()
                return
            }

            configure?(scrollView)
        }

        private func findScrollView() -> NSScrollView? {
            if let enclosingScrollView {
                return enclosingScrollView
            }

            var current: NSView? = superview

            while let view = current {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }

                if searchStrategy == .nearestOrFallback,
                   let scrollView = view.firstDescendant(of: NSScrollView.self) {
                    return scrollView
                }

                current = view.superview
            }

            guard searchStrategy == .nearestOrFallback else {
                return nil
            }

            return window?.contentView?.firstDescendant(of: NSScrollView.self)
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}

struct SelectableMonospacedTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    func makeNSView(context: Context) -> MeasuringSelectableTextView {
        let textView = MeasuringSelectableTextView(frame: .zero)
        textView.configure(fontSize: fontSize)
        textView.setText(text)
        return textView
    }

    func updateNSView(_ nsView: MeasuringSelectableTextView, context: Context) {
        nsView.configure(fontSize: fontSize)
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

    func configure(fontSize: CGFloat) {
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
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
