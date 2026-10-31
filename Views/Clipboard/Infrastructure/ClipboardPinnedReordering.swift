import AppKit
import QuartzCore
import SwiftUI

struct ClipboardPinnedDragItem: Identifiable, Sendable {
    let id: UUID
    let visualIndex: Int

    init(id: UUID, visualIndex: Int = 0) {
        self.id = id
        self.visualIndex = visualIndex
    }
}

/// Immutable geometry used while a pinned-row drag is active.
///
/// Adjacent rows share one canonical insertion boundary. Resolving a pointer
/// against row midpoints makes the spacing between rows part of the surrounding
/// drop zones instead of a transient no-target area.
struct ClipboardPinnedDropLayout: Equatable {
    struct Row: Equatable {
        let itemID: UUID
        let nextItemID: UUID?
        let frame: CGRect

        init(itemID: UUID, nextItemID: UUID? = nil, frame: CGRect) {
            self.itemID = itemID
            self.nextItemID = nextItemID
            self.frame = frame
        }
    }

    struct Target: Equatable {
        let destination: ClipboardPinnedReorderDestination
        let indicatorFrame: CGRect
    }

    private let isFlipped: Bool
    private let visualRowMidpoints: [CGFloat]
    private let targets: [Target]
    private let activationFrame: CGRect

    init?(
        rows: [Row],
        isFlipped: Bool,
        rowSpacing: CGFloat = ClipboardListStructure.LayoutMetrics.rowSpacing,
        horizontalIndicatorInset: CGFloat = 8,
        indicatorHeight: CGFloat = 2
    ) {
        let validRows =
            rows
            .filter { !$0.frame.isEmpty && !$0.frame.isNull && !$0.frame.isInfinite }
            .sorted {
                Self.visualCoordinate($0.frame.midY, isFlipped: isFlipped)
                    < Self.visualCoordinate($1.frame.midY, isFlipped: isFlipped)
            }
        guard let firstRow = validRows.first, let lastRow = validRows.last else {
            return nil
        }

        self.isFlipped = isFlipped
        visualRowMidpoints = validRows.map {
            Self.visualCoordinate($0.frame.midY, isFlipped: isFlipped)
        }

        var resolvedTargets: [Target] = []
        resolvedTargets.reserveCapacity(validRows.count + 1)
        for index in validRows.indices {
            let row = validRows[index]
            let centerY: CGFloat
            if index == validRows.startIndex {
                centerY = Self.offsetTowardVisualTop(
                    Self.visualTop(of: row.frame, isFlipped: isFlipped),
                    distance: rowSpacing / 2,
                    isFlipped: isFlipped
                )
            } else {
                let previousRow = validRows[validRows.index(before: index)]
                centerY =
                    (Self.visualBottom(of: previousRow.frame, isFlipped: isFlipped)
                        + Self.visualTop(of: row.frame, isFlipped: isFlipped)) / 2
            }
            resolvedTargets.append(
                Target(
                    destination: .before(row.itemID),
                    indicatorFrame: Self.indicatorFrame(
                        centeredAtY: centerY,
                        rowFrame: row.frame,
                        horizontalInset: horizontalIndicatorInset,
                        height: indicatorHeight
                    )
                )
            )
        }

        let endCenterY = Self.offsetTowardVisualBottom(
            Self.visualBottom(of: lastRow.frame, isFlipped: isFlipped),
            distance: rowSpacing / 2,
            isFlipped: isFlipped
        )
        resolvedTargets.append(
            Target(
                destination: lastRow.nextItemID.map(ClipboardPinnedReorderDestination.before) ?? .end,
                indicatorFrame: Self.indicatorFrame(
                    centeredAtY: endCenterY,
                    rowFrame: lastRow.frame,
                    horizontalInset: horizontalIndicatorInset,
                    height: indicatorHeight
                )
            )
        )
        targets = resolvedTargets

        let rowBounds = validRows.dropFirst().reduce(firstRow.frame) {
            $0.union($1.frame)
        }
        let verticalTolerance = max(
            rowSpacing * 2,
            min(ClipboardListStructure.LayoutMetrics.itemRowHeight / 2, lastRow.frame.height / 2)
        )
        activationFrame = rowBounds.insetBy(dx: -24, dy: -verticalTolerance)
    }

    func target(at point: CGPoint) -> Target? {
        guard activationFrame.contains(point), !targets.isEmpty else { return nil }

        let pointerY = Self.visualCoordinate(point.y, isFlipped: isFlipped)
        var lowerBound = 0
        var upperBound = visualRowMidpoints.count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if pointerY < visualRowMidpoints[midpoint] {
                upperBound = midpoint
            } else {
                lowerBound = midpoint + 1
            }
        }
        return targets[lowerBound]
    }

    private static func visualCoordinate(_ y: CGFloat, isFlipped: Bool) -> CGFloat {
        isFlipped ? y : -y
    }

    private static func visualTop(of frame: CGRect, isFlipped: Bool) -> CGFloat {
        isFlipped ? frame.minY : frame.maxY
    }

    private static func visualBottom(of frame: CGRect, isFlipped: Bool) -> CGFloat {
        isFlipped ? frame.maxY : frame.minY
    }

    private static func offsetTowardVisualTop(
        _ value: CGFloat,
        distance: CGFloat,
        isFlipped: Bool
    ) -> CGFloat {
        value + (isFlipped ? -distance : distance)
    }

    private static func offsetTowardVisualBottom(
        _ value: CGFloat,
        distance: CGFloat,
        isFlipped: Bool
    ) -> CGFloat {
        value + (isFlipped ? distance : -distance)
    }

    private static func indicatorFrame(
        centeredAtY centerY: CGFloat,
        rowFrame: CGRect,
        horizontalInset: CGFloat,
        height: CGFloat
    ) -> CGRect {
        CGRect(
            x: rowFrame.minX + horizontalInset,
            y: centerY - height / 2,
            width: max(0, rowFrame.width - horizontalInset * 2),
            height: height
        )
    }
}

enum ClipboardPinnedAutoscrollPolicy {
    static let edgeZone = CGFloat(28)
    static let minimumStep = CGFloat(2)
    static let maximumStep = CGFloat(8)

    static func delta(
        pointerY: CGFloat,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        guard viewportHeight > 0 else { return 0 }
        let viewportY = pointerY - scrollOffset
        if viewportY < edgeZone {
            let proximity = 1 - max(0, viewportY) / edgeZone
            return -max(minimumStep, maximumStep * proximity)
        }
        if viewportY > viewportHeight - edgeZone {
            let distance = max(0, viewportHeight - viewportY)
            let proximity = 1 - distance / edgeZone
            return max(minimumStep, maximumStep * proximity)
        }
        return 0
    }
}

@MainActor
private final class ClipboardPinnedDropIndicatorRenderer {
    private let layer = CALayer()
    private weak var containerLayer: CALayer?
    private var displayedFrame: CGRect?

    init(color: NSColor) {
        layer.backgroundColor = color.cgColor
        layer.cornerRadius = 1
        layer.opacity = 0
        layer.zPosition = 10_000
    }

    func updateColor(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    func show(frame: CGRect, in container: NSView, scale: CGFloat) {
        guard let nextContainerLayer = container.layer else {
            hide()
            return
        }

        let alignedFrame = pixelAligned(frame, scale: scale)
        guard !alignedFrame.isEmpty else {
            hide()
            return
        }
        if containerLayer !== nextContainerLayer {
            layer.removeFromSuperlayer()
            nextContainerLayer.addSublayer(layer)
            containerLayer = nextContainerLayer
            displayedFrame = nil
        }
        guard displayedFrame != alignedFrame || layer.opacity != 1 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.contentsScale = scale
        layer.frame = alignedFrame
        layer.opacity = 1
        CATransaction.commit()
        displayedFrame = alignedFrame
    }

    func hide() {
        guard layer.superlayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.opacity = 0
        layer.removeFromSuperlayer()
        CATransaction.commit()
        containerLayer = nil
        displayedFrame = nil
    }

    private func pixelAligned(_ frame: CGRect, scale: CGFloat) -> CGRect {
        let minimumX = (frame.minX * scale).rounded() / scale
        let maximumX = (frame.maxX * scale).rounded() / scale
        let centerY = (frame.midY * scale).rounded() / scale
        return CGRect(
            x: minimumX,
            y: centerY - frame.height / 2,
            width: max(0, maximumX - minimumX),
            height: frame.height
        )
    }
}

/// Bridges pinned-row pointer handling to AppKit's mouse tracking APIs.
///
/// SwiftUI's new reorder containers currently crash for UUID identifiers on
/// macOS 27, while a nested `NSDraggingSession` can lose its mouse-up when the
/// SwiftUI hierarchy relayouts. Keeping the pointer lifecycle in one stable
/// `NSView` preserves AppKit's drag threshold and cursor semantics without
/// invalidating the list while the pointer moves.
struct ClipboardPinnedRowDragBridge: NSViewRepresentable {
    let itemID: UUID
    let nextItemID: UUID?
    let onBeginDrag: () -> Bool
    let canAcceptDrop: () -> Bool
    let onPreviewDrop: (ClipboardPinnedReorderDestination) -> Bool
    let onPerformDrop: (ClipboardPinnedReorderDestination) -> Void
    let onDragLocationChanged: (CGFloat, @escaping @MainActor () -> Void) -> Void
    let onDragEnded: () -> Void
    let onPrimaryMouseDown: (NSEvent.ModifierFlags) -> Bool
    let onClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let onSecondaryClick: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onPointerMoved: () -> Void
    let contextMenuActions: [HistoryItemActionDescriptor]
    let onContextMenuAction: (HistoryItemAction) -> Void
    let onContextMenuDismissed: () -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        update(nsView)
    }

    private func update(_ view: InteractionView) {
        view.itemID = itemID
        view.nextItemID = nextItemID
        view.onBeginDrag = onBeginDrag
        view.canAcceptDrop = canAcceptDrop
        view.onPreviewDrop = onPreviewDrop
        view.onPerformDrop = onPerformDrop
        view.onDragLocationChanged = onDragLocationChanged
        view.onDragEnded = onDragEnded
        view.onPrimaryMouseDown = onPrimaryMouseDown
        view.onClickWithModifiers = onClickWithModifiers
        view.onDoubleClick = onDoubleClick
        view.onSecondaryClick = onSecondaryClick
        view.onHoverChanged = onHoverChanged
        view.onPointerMoved = onPointerMoved
        view.contextMenuActions = contextMenuActions
        view.onContextMenuAction = onContextMenuAction
        view.onContextMenuDismissed = onContextMenuDismissed
    }

    final class InteractionView: NSView, NSMenuDelegate {
        private struct DropLayoutCache {
            let containerID: ObjectIdentifier
            let containerSize: CGSize
            let visibleOrigin: CGPoint
            let layout: ClipboardPinnedDropLayout
        }

        var itemID = UUID()
        var nextItemID: UUID?
        var onBeginDrag: (() -> Bool)?
        var canAcceptDrop: (() -> Bool)?
        var onPreviewDrop: ((ClipboardPinnedReorderDestination) -> Bool)?
        var onPerformDrop: ((ClipboardPinnedReorderDestination) -> Void)?
        var onDragLocationChanged: ((CGFloat, @escaping @MainActor () -> Void) -> Void)?
        var onDragEnded: (() -> Void)?
        var onPrimaryMouseDown: ((NSEvent.ModifierFlags) -> Bool)?
        var onClickWithModifiers: ((NSEvent.ModifierFlags) -> Void)?
        var onDoubleClick: (() -> Void)?
        var onSecondaryClick: (() -> Void)?
        var onHoverChanged: ((Bool) -> Void)?
        var onPointerMoved: (() -> Void)?
        var contextMenuActions: [HistoryItemActionDescriptor] = []
        var onContextMenuAction: ((HistoryItemAction) -> Void)?
        var onContextMenuDismissed: (() -> Void)?

        private let dragThreshold = CGFloat(3)
        private var dropIndicatorRenderer: ClipboardPinnedDropIndicatorRenderer?
        private var initialMouseDownEvent: NSEvent?
        private var lastDragLocationInWindow: CGPoint?
        private var didBeginDragging = false
        private var didPushDragCursor = false
        private var handledSelectionOnMouseDown = false
        private var dropLayoutCache: DropLayoutCache?
        private var resolvedDestination: ClipboardPinnedReorderDestination?
        private var activeDestination: ClipboardPinnedReorderDestination?
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }
        override var intrinsicContentSize: NSSize {
            NSSize(width: 1, height: 1)
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            dropIndicatorRenderer?.updateColor(.controlAccentColor)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                onHoverChanged?(false)
                if didBeginDragging {
                    let dragEnded = onDragEnded
                    finishManualDrag()
                    dragEnded?()
                }
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            guard !didBeginDragging else { return }
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }

        override func mouseMoved(with event: NSEvent) {
            guard !didBeginDragging else { return }
            onPointerMoved?()
        }

        override func mouseDown(with event: NSEvent) {
            initialMouseDownEvent = event
            didBeginDragging = false
            handledSelectionOnMouseDown = onPrimaryMouseDown?(event.modifierFlags) == true
        }

        override func mouseDragged(with event: NSEvent) {
            if !didBeginDragging {
                guard let initialMouseDownEvent,
                    exceedsDragThreshold(from: initialMouseDownEvent, to: event),
                    onBeginDrag?() == true
                else { return }

                didBeginDragging = true
                dropLayoutCache = nil
                onHoverChanged?(false)
                NSCursor.closedHand.push()
                didPushDragCursor = true
            }

            lastDragLocationInWindow = event.locationInWindow
            updateManualDrag(at: event.locationInWindow, updatesAutoscroll: true)
        }

        override func mouseUp(with event: NSEvent) {
            if didBeginDragging {
                let destination = activeDestination
                let performDrop = onPerformDrop
                let dragEnded = onDragEnded
                finishManualDrag()
                if let destination {
                    performDrop?(destination)
                }
                dragEnded?()
                return
            }

            initialMouseDownEvent = nil

            if event.clickCount == 2 {
                onDoubleClick?()
            } else if !handledSelectionOnMouseDown {
                onClickWithModifiers?(event.modifierFlags)
            }
            handledSelectionOnMouseDown = false
        }

        override func rightMouseDown(with event: NSEvent) {
            onSecondaryClick?()
            let menu = makeContextMenu()
            guard !menu.items.isEmpty else {
                onContextMenuDismissed?()
                return
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        func menuDidClose(_ menu: NSMenu) {
            onContextMenuDismissed?()
        }

        override func cancelOperation(_ sender: Any?) {
            guard didBeginDragging else {
                super.cancelOperation(sender)
                return
            }
            let dragEnded = onDragEnded
            finishManualDrag()
            dragEnded?()
        }

        private func exceedsDragThreshold(from start: NSEvent, to current: NSEvent) -> Bool {
            let deltaX = current.locationInWindow.x - start.locationInWindow.x
            let deltaY = current.locationInWindow.y - start.locationInWindow.y
            return hypot(deltaX, deltaY) >= dragThreshold
        }

        private func makeContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self

            for (index, descriptor) in contextMenuActions.enumerated() {
                if index > 0, descriptor.isDestructive {
                    menu.addItem(.separator())
                }

                let item = NSMenuItem(
                    title: descriptor.title,
                    action: #selector(performContextMenuAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                item.isEnabled = descriptor.isEnabled
                menu.addItem(item)
            }
            return menu
        }

        @objc
        private func performContextMenuAction(_ sender: NSMenuItem) {
            guard contextMenuActions.indices.contains(sender.tag) else { return }
            onContextMenuAction?(contextMenuActions[sender.tag].action)
        }

        private func updateManualDrag(
            at locationInWindow: CGPoint,
            updatesAutoscroll: Bool
        ) {
            guard canAcceptDrop?() == true,
                let container = enclosingScrollView?.documentView ?? window?.contentView
            else {
                clearActiveDestination()
                return
            }

            let pointInContainer = container.convert(locationInWindow, from: nil)
            guard let layout = dropLayout(in: container),
                let target = layout.target(at: pointInContainer)
            else {
                clearActiveDestination()
                if updatesAutoscroll {
                    updateAutoscroll(
                        at: locationInWindow,
                        in: container
                    )
                }
                return
            }

            if resolvedDestination != target.destination {
                resolvedDestination = target.destination
                activeDestination =
                    onPreviewDrop?(target.destination) == true
                    ? target.destination
                    : nil
            }

            if activeDestination != nil {
                indicatorRenderer.show(
                    frame: target.indicatorFrame,
                    in: container,
                    scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
                )
            } else {
                dropIndicatorRenderer?.hide()
            }
            if updatesAutoscroll {
                updateAutoscroll(
                    at: locationInWindow,
                    in: container
                )
            }
        }

        private func updateAutoscroll(
            at locationInWindow: CGPoint,
            in documentView: NSView
        ) {
            let pointInDocument = documentView.convert(locationInWindow, from: nil)
            let pointerY =
                documentView.isFlipped
                ? pointInDocument.y
                : documentView.bounds.height - pointInDocument.y
            onDragLocationChanged?(pointerY) { [weak self] in
                self?.refreshAfterAutoscroll()
            }
        }

        private func refreshAfterAutoscroll() {
            guard didBeginDragging, let lastDragLocationInWindow else { return }
            updateManualDrag(
                at: lastDragLocationInWindow,
                updatesAutoscroll: false
            )
        }

        private func clearActiveDestination() {
            dropIndicatorRenderer?.hide()
            resolvedDestination = nil
            activeDestination = nil
        }

        private func finishManualDrag() {
            clearActiveDestination()
            if didPushDragCursor {
                NSCursor.pop()
            }
            didPushDragCursor = false
            didBeginDragging = false
            handledSelectionOnMouseDown = false
            initialMouseDownEvent = nil
            lastDragLocationInWindow = nil
            dropLayoutCache = nil
            dropIndicatorRenderer = nil
        }

        private func dropLayout(in container: NSView) -> ClipboardPinnedDropLayout? {
            let visibleOrigin = container.visibleRect.origin
            let refreshDistance = ClipboardListStructure.LayoutMetrics.itemRowHeight / 2
            if let dropLayoutCache,
                dropLayoutCache.containerID == ObjectIdentifier(container),
                dropLayoutCache.containerSize == container.bounds.size,
                abs(dropLayoutCache.visibleOrigin.x - visibleOrigin.x) < refreshDistance,
                abs(dropLayoutCache.visibleOrigin.y - visibleOrigin.y) < refreshDistance
            {
                return dropLayoutCache.layout
            }

            var rowByItemID: [UUID: (row: ClipboardPinnedDropLayout.Row, visibleArea: CGFloat)] = [:]
            for interactionView in interactionViews(in: container) {
                let frame = interactionView.convert(interactionView.bounds, to: container)
                guard !frame.isEmpty, !frame.isNull, !frame.isInfinite else { continue }
                let visibleIntersection = frame.intersection(container.visibleRect)
                let visibleArea =
                    visibleIntersection.isNull
                    ? 0
                    : visibleIntersection.width * visibleIntersection.height
                let row = ClipboardPinnedDropLayout.Row(
                    itemID: interactionView.itemID,
                    nextItemID: interactionView.nextItemID,
                    frame: frame
                )
                if let existing = rowByItemID[interactionView.itemID],
                    existing.visibleArea > visibleArea
                {
                    continue
                }
                rowByItemID[interactionView.itemID] = (row, visibleArea)
            }

            guard
                let layout = ClipboardPinnedDropLayout(
                    rows: rowByItemID.values.map(\.row),
                    isFlipped: container.isFlipped
                )
            else {
                dropLayoutCache = nil
                return nil
            }
            dropLayoutCache = DropLayoutCache(
                containerID: ObjectIdentifier(container),
                containerSize: container.bounds.size,
                visibleOrigin: visibleOrigin,
                layout: layout
            )
            return layout
        }

        private func interactionViews(in rootView: NSView) -> [InteractionView] {
            var result: [InteractionView] = []
            var pendingViews = rootView.subviews
            while let view = pendingViews.popLast() {
                if let interactionView = view as? InteractionView {
                    guard !interactionView.isHidden, interactionView.window === window else { continue }
                    result.append(interactionView)
                    continue
                }
                pendingViews.append(contentsOf: view.subviews)
            }
            return result
        }

        private var indicatorRenderer: ClipboardPinnedDropIndicatorRenderer {
            if let dropIndicatorRenderer {
                return dropIndicatorRenderer
            }
            let renderer = ClipboardPinnedDropIndicatorRenderer(color: .controlAccentColor)
            dropIndicatorRenderer = renderer
            return renderer
        }
    }
}

enum ClipboardPinnedAccessibilityMove {
    case up
    case down
}

@MainActor
final class ClipboardPinnedReorderCoordinator: ObservableObject {
    @Published private(set) var displayedItemIDs: [UUID] = []
    private(set) var isCommitInFlight = false

    private var authoritativeItemIDs: [UUID] = []
    private var dragBaselineItemIDs: [UUID]?
    private var draggedItemIDs: [UUID] = []
    private var pendingDropRequest: ClipboardPinnedReorderRequest?
    private var pendingCommittedItemIDs: [UUID]?
    private var pendingCommitAnimation: Animation?
    private var acceptedDrop = false
    private var autoscrollDelta = CGFloat.zero
    private var autoscrollTask: Task<Void, Never>?

    deinit {
        autoscrollTask?.cancel()
    }

    func synchronize(authoritativeItemIDs: [UUID], allowsReordering: Bool) {
        guard allowsReordering else {
            self.authoritativeItemIDs = authoritativeItemIDs
            updateDisplayedItemIDs(authoritativeItemIDs)
            resetDragState()
            return
        }

        self.authoritativeItemIDs = authoritativeItemIDs
        if authoritativeItemIDs == pendingCommittedItemIDs {
            updateDisplayedItemIDs(authoritativeItemIDs)
            pendingCommittedItemIDs = nil
            pendingCommitAnimation = nil
            dragBaselineItemIDs = nil
            return
        }

        if let dragBaselineItemIDs,
            authoritativeItemIDs != dragBaselineItemIDs,
            !isCommitInFlight
        {
            resetDragState()
        }

        if displayedItemIDs.isEmpty
            || displayedItemIDs == dragBaselineItemIDs
            || displayedItemIDs == authoritativeItemIDs
            || (!hasActiveDrag && !isCommitInFlight)
        {
            updateDisplayedItemIDs(authoritativeItemIDs)
        }
    }

    func beginDrag(
        itemID: UUID,
        selectedItemIDs: Set<UUID>
    ) -> [ClipboardPinnedDragItem] {
        guard !isCommitInFlight, displayedItemIDs.contains(itemID) else { return [] }

        let selectedPinnedIDs = displayedItemIDs.filter(selectedItemIDs.contains)
        draggedItemIDs = selectedItemIDs.contains(itemID) ? selectedPinnedIDs : [itemID]
        if draggedItemIDs.isEmpty {
            draggedItemIDs = [itemID]
        }
        dragBaselineItemIDs = authoritativeItemIDs
        acceptedDrop = false
        pendingDropRequest = nil
        return draggedItemIDs.map { ClipboardPinnedDragItem(id: $0) }
    }

    @discardableResult
    func preview(destination: ClipboardPinnedReorderDestination) -> Bool {
        guard hasActiveDrag else { return false }
        let request = ClipboardPinnedReorderRequest(
            movingItemIDs: draggedItemIDs,
            destination: destination
        )
        guard
            ClipboardPinnedOrderResolver().reorderedItemIDs(
                currentItemIDs: authoritativeItemIDs,
                request: request
            ) != nil
        else {
            pendingDropRequest = nil
            return false
        }

        pendingDropRequest = request
        return true
    }

    func acceptDrop(
        destination: ClipboardPinnedReorderDestination,
        animation: Animation?,
        commit: @escaping @MainActor (ClipboardPinnedReorderRequest) async -> Bool
    ) {
        guard hasActiveDrag else { return }
        preview(destination: destination)
        acceptedDrop = true
        let request = pendingDropRequest
        finishDrag()
        guard let request else {
            updateDisplayedItemIDs(authoritativeItemIDs)
            dragBaselineItemIDs = nil
            return
        }
        pendingCommittedItemIDs = ClipboardPinnedOrderResolver().reorderedItemIDs(
            currentItemIDs: authoritativeItemIDs,
            request: request
        )
        pendingCommitAnimation = animation
        if let pendingCommittedItemIDs {
            withAnimation(animation) {
                displayedItemIDs = pendingCommittedItemIDs
            }
        }
        commitReorder(request, commit: commit)
    }

    func accessibilityRequest(
        for itemID: UUID,
        direction: ClipboardPinnedAccessibilityMove,
        selectedItemIDs: Set<UUID>
    ) -> ClipboardPinnedReorderRequest? {
        let movingIDs: [UUID]
        if selectedItemIDs.contains(itemID) {
            movingIDs = displayedItemIDs.filter(selectedItemIDs.contains)
        } else {
            movingIDs = [itemID]
        }
        let movingIDSet = Set(movingIDs)
        guard !movingIDs.isEmpty else { return nil }

        switch direction {
        case .up:
            guard let firstMovingIndex = displayedItemIDs.firstIndex(where: movingIDSet.contains),
                let previousID = displayedItemIDs[..<firstMovingIndex].last(where: { !movingIDSet.contains($0) })
            else { return nil }
            return ClipboardPinnedReorderRequest(
                movingItemIDs: movingIDs,
                destination: .before(previousID)
            )

        case .down:
            guard let lastMovingIndex = displayedItemIDs.lastIndex(where: movingIDSet.contains),
                let nextIndex = displayedItemIDs[lastMovingIndex...]
                    .firstIndex(where: { !movingIDSet.contains($0) })
            else { return nil }
            let followingID = displayedItemIDs[displayedItemIDs.index(after: nextIndex)...]
                .first(where: { !movingIDSet.contains($0) })
            return ClipboardPinnedReorderRequest(
                movingItemIDs: movingIDs,
                destination: followingID.map(ClipboardPinnedReorderDestination.before) ?? .end
            )
        }
    }

    func commitAccessibilityMove(
        _ request: ClipboardPinnedReorderRequest,
        animation: Animation?,
        commit: @escaping @MainActor (ClipboardPinnedReorderRequest) async -> Bool
    ) {
        guard !isCommitInFlight,
            let reorderedIDs = ClipboardPinnedOrderResolver().reorderedItemIDs(
                currentItemIDs: displayedItemIDs,
                request: request
            )
        else { return }
        dragBaselineItemIDs = authoritativeItemIDs
        withAnimation(animation) {
            displayedItemIDs = reorderedIDs
        }
        commitReorder(request, commit: commit)
    }

    func dragSessionEnded() {
        stopAutoscroll()
        guard hasActiveDrag, !acceptedDrop else { return }
        cancelDrag()
    }

    func cancelDrag() {
        updateDisplayedItemIDs(dragBaselineItemIDs ?? authoritativeItemIDs)
        resetDragState()
    }

    func updateAutoscroll(
        pointerY: CGFloat,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        scrollBy: @escaping @MainActor (CGFloat) -> Bool,
        onAutoscrollFrame: @escaping @MainActor () -> Void
    ) {
        guard hasActiveDrag, viewportHeight > 0 else {
            stopAutoscroll()
            return
        }

        let nextDelta = ClipboardPinnedAutoscrollPolicy.delta(
            pointerY: pointerY,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight
        )

        guard nextDelta != 0 else {
            stopAutoscroll()
            return
        }
        autoscrollDelta = nextDelta
        guard autoscrollTask == nil else { return }

        autoscrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled, autoscrollDelta != 0 else { return }
                guard scrollBy(autoscrollDelta) else {
                    stopAutoscroll()
                    return
                }
                onAutoscrollFrame()
            }
        }
    }

    var hasActiveDrag: Bool {
        !draggedItemIDs.isEmpty
    }

    private func commitReorder(
        _ request: ClipboardPinnedReorderRequest,
        commit: @escaping @MainActor (ClipboardPinnedReorderRequest) async -> Bool
    ) {
        isCommitInFlight = true
        Task { @MainActor [weak self] in
            let didCommit = await commit(request)
            guard let self else { return }
            isCommitInFlight = false
            guard didCommit else {
                withAnimation(self.pendingCommitAnimation) {
                    self.displayedItemIDs = self.dragBaselineItemIDs ?? self.authoritativeItemIDs
                }
                dragBaselineItemIDs = nil
                pendingCommittedItemIDs = nil
                pendingCommitAnimation = nil
                return
            }

            // Keep the optimistic order until `synchronize` receives the
            // authoritative repository snapshot.
            if authoritativeItemIDs == displayedItemIDs {
                dragBaselineItemIDs = nil
            }
        }
    }

    private func finishDrag() {
        draggedItemIDs = []
        stopAutoscroll()
    }

    private func resetDragState() {
        draggedItemIDs = []
        pendingDropRequest = nil
        pendingCommittedItemIDs = nil
        pendingCommitAnimation = nil
        dragBaselineItemIDs = nil
        acceptedDrop = false
        stopAutoscroll()
    }

    private func stopAutoscroll() {
        autoscrollTask?.cancel()
        autoscrollTask = nil
        autoscrollDelta = 0
    }

    private func updateDisplayedItemIDs(_ itemIDs: [UUID]) {
        guard displayedItemIDs != itemIDs else { return }
        displayedItemIDs = itemIDs
    }
}
