import AppKit

final class ScrollbarThumbInteractionView: NSView {
    private var state = ScrollbarThumbInteractionState()
    private var onScroll: ((CGFloat) -> Void)?

    private let thumbLayer = CALayer()

    private let hoverAnimationDuration: CFTimeInterval = 0.14

    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        thumbLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.22).cgColor
        thumbLayer.masksToBounds = true

        layer?.addSublayer(thumbLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func layout() {
        super.layout()
        updateThumbLayer(animated: false)
    }

    func updateMetrics(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        scrollbarWidth: CGFloat,
        scrollOffset: CGFloat,
        onScroll: @escaping (CGFloat) -> Void
    ) {
        self.onScroll = onScroll
        state.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollbarWidth: scrollbarWidth,
            scrollOffset: scrollOffset
        )

        // The thumb represents the viewport and must never lag behind it. Repeated
        // implicit position animations accumulate latency during long scrolls and
        // race to catch up when direction reverses.
        updateThumbLayer(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited
            ],
            owner: self,
            userInfo: nil
        )

        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        state.beginHover()
        updateThumbLayer(
            animated: true,
            duration: hoverAnimationDuration
        )
    }

    override func mouseExited(with event: NSEvent) {
        state.endHover()
        updateThumbLayer(
            animated: true,
            duration: hoverAnimationDuration
        )
    }

    override func mouseDown(with event: NSEvent) {
        let mouseY = topOriginMouseY(for: event)
        if let progress = state.beginDrag(
            mouseY: mouseY,
            trackHeight: bounds.height
        ) {
            onScroll?(progress)
        }

        updateThumbLayer(
            animated: true,
            duration: hoverAnimationDuration
        )
    }

    override func mouseDragged(with event: NSEvent) {
        let mouseY = topOriginMouseY(for: event)
        if let progress = state.drag(mouseY: mouseY, trackHeight: bounds.height) {
            updateThumbLayer(animated: false)
            onScroll?(progress)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let mouseY = topOriginMouseY(for: event)
        state.endDrag(mouseY: mouseY, boundsHeight: bounds.height)

        updateThumbLayer(
            animated: true,
            duration: hoverAnimationDuration
        )
    }

    private func topOriginMouseY(for event: NSEvent) -> CGFloat {
        let location = convert(event.locationInWindow, from: nil)
        return location.y.clamped(to: 0...bounds.height)
    }

    private func updateThumbLayer(
        animated: Bool,
        duration: CFTimeInterval = 0
    ) {
        let model = state.layerModel(for: bounds)

        guard !model.isHidden else {
            thumbLayer.isHidden = true
            return
        }

        thumbLayer.isHidden = false

        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(animated ? duration : 0)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeOut)
        )

        thumbLayer.frame = model.frame
        thumbLayer.cornerRadius = model.cornerRadius
        thumbLayer.backgroundColor = NSColor.labelColor
            .withAlphaComponent(model.alpha)
            .cgColor

        CATransaction.commit()
    }
}
