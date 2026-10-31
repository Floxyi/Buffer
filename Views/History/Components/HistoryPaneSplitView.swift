import AppKit
import SwiftUI

struct HistoryPaneSplitConfiguration: Equatable, Sendable {
    let minimumListWidth: CGFloat
    let preferredListWidth: CGFloat
    let minimumDetailWidth: CGFloat
    let dividerHitWidth: CGFloat
    let persistenceIdentifier: String?

    static let standard = HistoryPaneSplitConfiguration(
        minimumListWidth: 260,
        preferredListWidth: 300,
        minimumDetailWidth: 360,
        dividerHitWidth: 9,
        persistenceIdentifier: "Buffer.HistoryWindow.PaneSplit"
    )

    static let ephemeral = HistoryPaneSplitConfiguration(
        minimumListWidth: standard.minimumListWidth,
        preferredListWidth: standard.preferredListWidth,
        minimumDetailWidth: standard.minimumDetailWidth,
        dividerHitWidth: standard.dividerHitWidth,
        persistenceIdentifier: nil
    )
}

struct HistoryPaneSplitView<Leading: View, Trailing: View>: NSViewRepresentable {
    @Environment(\.bufferAppearance) private var appearance

    let configuration: HistoryPaneSplitConfiguration
    let initialWidth: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(
        configuration: HistoryPaneSplitConfiguration,
        initialWidth: CGFloat,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.configuration = configuration
        self.initialWidth = initialWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    func makeCoordinator() -> HistoryPaneSplitCoordinator {
        HistoryPaneSplitCoordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> HistoryPaneNativeSplitView {
        let splitView = HistoryPaneNativeSplitView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: max(initialWidth, preferredInitialSplitWidth),
                height: 1
            )
        )
        context.coordinator.install(
            in: splitView,
            leading: hostedRoot(leading),
            trailing: hostedRoot(trailing)
        )
        return splitView
    }

    func updateNSView(_ splitView: HistoryPaneNativeSplitView, context: Context) {
        context.coordinator.update(
            configuration: configuration,
            leading: hostedRoot(leading),
            trailing: hostedRoot(trailing),
            in: splitView
        )
    }

    private func hostedRoot<Content: View>(_ content: Content) -> AnyView {
        AnyView(
            content
                .environment(\.bufferAppearance, appearance)
                .preferredColorScheme(appearance.mode.colorScheme)
        )
    }

    private var preferredInitialSplitWidth: CGFloat {
        configuration.preferredListWidth + configuration.minimumDetailWidth + 1
    }
}

final class HistoryPaneNativeSplitView: NSSplitView {
    private var dividerTrackingArea: NSTrackingArea?

    var dividerHitWidth = CGFloat(9) {
        didSet {
            guard dividerHitWidth != oldValue else { return }
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }

    override var dividerThickness: CGFloat { 1 }

    override var dividerColor: NSColor {
        NSColor.labelColor.withAlphaComponent(0.12)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let interactionRect = dividerInteractionRect(at: 0) else { return }
        addCursorRect(interactionRect, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        if let dividerTrackingArea {
            removeTrackingArea(dividerTrackingArea)
        }

        super.updateTrackingAreas()

        guard let interactionRect = dividerInteractionRect(at: 0) else {
            dividerTrackingArea = nil
            return
        }

        let dividerTrackingArea = NSTrackingArea(
            rect: interactionRect,
            options: [
                .activeAlways,
                .cursorUpdate,
                .enabledDuringMouseDrag,
                .mouseEnteredAndExited,
                .mouseMoved,
            ],
            owner: self
        )
        addTrackingArea(dividerTrackingArea)
        self.dividerTrackingArea = dividerTrackingArea
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isOverDivider(event) else {
            super.cursorUpdate(with: event)
            return
        }

        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        if isOverDivider(event) {
            NSCursor.resizeLeftRight.set()
        } else {
            super.mouseEntered(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if isOverDivider(event) {
            NSCursor.resizeLeftRight.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    func dividerInteractionRect(at dividerIndex: Int) -> NSRect? {
        guard dividerIndex >= 0, dividerIndex < arrangedSubviews.count - 1 else {
            return nil
        }

        let dividerCenterX = arrangedSubviews[dividerIndex].frame.maxX + dividerThickness / 2
        let interactionWidth = max(dividerHitWidth, dividerThickness)
        return NSRect(
            x: dividerCenterX - interactionWidth / 2,
            y: bounds.minY,
            width: interactionWidth,
            height: max(0, bounds.height)
        )
    }

    private func isOverDivider(_ event: NSEvent) -> Bool {
        let location = convert(event.locationInWindow, from: nil)
        return dividerInteractionRect(at: 0)?.contains(location) == true
    }
}

@MainActor
final class HistoryPaneSplitCoordinator: NSObject, NSSplitViewDelegate {
    private enum HoldingPriority {
        static let list = NSLayoutConstraint.Priority(rawValue: 251)
        static let detail = NSLayoutConstraint.Priority(rawValue: 250)
    }

    private(set) var configuration: HistoryPaneSplitConfiguration
    private(set) var leadingHostingView: NSHostingView<AnyView>?
    private(set) var trailingHostingView: NSHostingView<AnyView>?
    private let defaults: UserDefaults
    private var isReadyToPersistDividerPosition = false
    private var pendingRestoredListWidth: CGFloat?

    init(
        configuration: HistoryPaneSplitConfiguration,
        defaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.defaults = defaults
    }

    func install(
        in splitView: HistoryPaneNativeSplitView,
        leading: AnyView,
        trailing: AnyView
    ) {
        precondition(splitView.arrangedSubviews.isEmpty)

        let leadingHostingView = makeHostingView(
            rootView: leading,
            width: configuration.preferredListWidth,
            identifier: "historyListPane"
        )
        let trailingHostingView = makeHostingView(
            rootView: trailing,
            width: configuration.minimumDetailWidth,
            identifier: "historyDetailPane"
        )
        self.leadingHostingView = leadingHostingView
        self.trailingHostingView = trailingHostingView

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.dividerHitWidth = configuration.dividerHitWidth
        splitView.delegate = self
        splitView.identifier = NSUserInterfaceItemIdentifier("historyPaneSplit")
        splitView.addArrangedSubview(leadingHostingView)
        splitView.addArrangedSubview(trailingHostingView)
        applyHoldingPriorities(to: splitView)
        splitView.adjustSubviews()
        restoreDividerPosition(in: splitView)
        isReadyToPersistDividerPosition = true
    }

    func update(
        configuration: HistoryPaneSplitConfiguration,
        leading: AnyView,
        trailing: AnyView,
        in splitView: HistoryPaneNativeSplitView
    ) {
        let previousPersistenceIdentifier = self.configuration.persistenceIdentifier
        self.configuration = configuration
        splitView.dividerHitWidth = configuration.dividerHitWidth
        leadingHostingView?.rootView = leading
        trailingHostingView?.rootView = trailing
        if previousPersistenceIdentifier != configuration.persistenceIdentifier {
            isReadyToPersistDividerPosition = false
            restoreDividerPosition(in: splitView)
            isReadyToPersistDividerPosition = true
        }
        applyHoldingPriorities(to: splitView)
        constrainCurrentDividerPosition(in: splitView)
        splitView.needsDisplay = true
    }

    func splitView(
        _ splitView: NSSplitView,
        canCollapseSubview subview: NSView
    ) -> Bool {
        false
    }

    func splitView(
        _ splitView: NSSplitView,
        shouldHideDividerAt dividerIndex: Int
    ) -> Bool {
        false
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? HistoryPaneNativeSplitView else { return }
        splitView.updateTrackingAreas()
        splitView.window?.invalidateCursorRects(for: splitView)
        persistDividerPosition(from: splitView)
    }

    func splitView(
        _ splitView: NSSplitView,
        resizeSubviewsWithOldSize oldSize: NSSize
    ) {
        guard splitView.isVertical, splitView.arrangedSubviews.count == 2 else {
            splitView.adjustSubviews()
            return
        }

        let listView = splitView.arrangedSubviews[0]
        let detailView = splitView.arrangedSubviews[1]
        let availableWidth = max(0, splitView.bounds.width - splitView.dividerThickness)
        let maximumListWidth = max(0, availableWidth - configuration.minimumDetailWidth)
        let minimumListWidth = min(configuration.minimumListWidth, maximumListWidth)
        let desiredListWidth = pendingRestoredListWidth ?? listView.frame.width
        if desiredListWidth > maximumListWidth {
            pendingRestoredListWidth = desiredListWidth
        }
        let restoredListWidth = pendingRestoredListWidth.flatMap { width in
            width <= maximumListWidth ? width : nil
        }
        let listWidth = min(
            max(restoredListWidth ?? listView.frame.width, minimumListWidth),
            maximumListWidth
        )
        if restoredListWidth != nil {
            pendingRestoredListWidth = nil
        }
        let detailOriginX = splitView.bounds.minX + listWidth + splitView.dividerThickness

        listView.frame = NSRect(
            x: splitView.bounds.minX,
            y: splitView.bounds.minY,
            width: listWidth,
            height: splitView.bounds.height
        )
        detailView.frame = NSRect(
            x: detailOriginX,
            y: splitView.bounds.minY,
            width: max(0, splitView.bounds.maxX - detailOriginX),
            height: splitView.bounds.height
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMinimumPosition }
        return max(proposedMinimumPosition, configuration.minimumListWidth)
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMaximumPosition }
        return min(proposedMaximumPosition, maximumDividerPosition(in: splitView))
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else { return proposedPosition }
        return min(
            max(proposedPosition, configuration.minimumListWidth),
            maximumDividerPosition(in: splitView)
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        additionalEffectiveRectOfDividerAt dividerIndex: Int
    ) -> NSRect {
        guard dividerIndex == 0, let leadingView = splitView.arrangedSubviews.first else {
            return .zero
        }

        return (splitView as? HistoryPaneNativeSplitView)?.dividerInteractionRect(
            at: dividerIndex
        )
            ?? NSRect(
                x: leadingView.frame.maxX,
                y: splitView.bounds.minY,
                width: 0,
                height: max(0, splitView.bounds.height)
            )
    }

    private func makeHostingView(
        rootView: AnyView,
        width: CGFloat,
        identifier: String
    ) -> NSHostingView<AnyView> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 1)
        hostingView.identifier = NSUserInterfaceItemIdentifier(identifier)
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return hostingView
    }

    private func applyHoldingPriorities(to splitView: NSSplitView) {
        guard splitView.arrangedSubviews.count == 2 else { return }
        splitView.setHoldingPriority(
            HoldingPriority.list,
            forSubviewAt: 0
        )
        splitView.setHoldingPriority(
            HoldingPriority.detail,
            forSubviewAt: 1
        )
    }

    private func constrainCurrentDividerPosition(in splitView: NSSplitView) {
        guard
            splitView.arrangedSubviews.count == 2,
            splitView.bounds.width
                >= configuration.minimumListWidth
                + splitView.dividerThickness
                + configuration.minimumDetailWidth
        else {
            return
        }

        let currentPosition = splitView.arrangedSubviews[0].frame.maxX
        let constrainedPosition = self.splitView(
            splitView,
            constrainSplitPosition: currentPosition,
            ofSubviewAt: 0
        )
        if currentPosition != constrainedPosition {
            splitView.setPosition(constrainedPosition, ofDividerAt: 0)
        }
    }

    private func restoreDividerPosition(in splitView: NSSplitView) {
        let storedWidth = configuration.persistenceIdentifier.flatMap { identifier in
            defaults.object(
                forKey: HistoryLayoutPersistence.paneListWidthDefaultsKey(
                    for: identifier
                )
            ) as? NSNumber
        }?.doubleValue
        let preferredWidth =
            storedWidth.flatMap { $0.isFinite ? CGFloat($0) : nil }
            ?? configuration.preferredListWidth
        pendingRestoredListWidth = preferredWidth
        let position = self.splitView(
            splitView,
            constrainSplitPosition: preferredWidth,
            ofSubviewAt: 0
        )
        splitView.setPosition(position, ofDividerAt: 0)
        if position == preferredWidth {
            pendingRestoredListWidth = nil
        }
    }

    private func persistDividerPosition(from splitView: NSSplitView) {
        guard
            isReadyToPersistDividerPosition,
            pendingRestoredListWidth == nil,
            let persistenceIdentifier = configuration.persistenceIdentifier,
            let leadingView = splitView.arrangedSubviews.first
        else {
            return
        }

        defaults.set(
            Double(leadingView.frame.width),
            forKey: HistoryLayoutPersistence.paneListWidthDefaultsKey(
                for: persistenceIdentifier
            )
        )
    }

    private func maximumDividerPosition(in splitView: NSSplitView) -> CGFloat {
        max(
            configuration.minimumListWidth,
            splitView.bounds.width
                - splitView.dividerThickness
                - configuration.minimumDetailWidth
        )
    }
}
