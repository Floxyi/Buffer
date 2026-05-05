import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation.
struct ClipboardListView: View {
    private let topScrollAnchorID = "history-list-top"
    private let calendar = Calendar.current

    @StateObject private var scrollController = ScrollController()

    let items: [ClipboardItem]
    
    @Binding var selectedIndex: Int
    @Binding var scrollTrigger: Bool
    
    let store: ClipboardStore
    let showsQuickPasteNumbers: Bool
    let onSelect: (ClipboardItem) -> Void
    let onPaste: (ClipboardItem) -> Void
    let onDelete: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    // Multi-select support
    @Binding var selectedIDs: Set<UUID>
    var onSelectSingle: (UUID) -> Void = { _ in }
    var onToggleSelection: (UUID) -> Void = { _ in }
    var onExtendSelectionTo: (UUID) -> Void = { _ in }

    private struct ItemSection: Identifiable {
        let id: String
        let title: String
        var items: [ClipboardItem]
    }

    private struct DisplayRow: Identifiable {
        enum Kind {
            case header(title: String, systemImage: String?)
            case divider
            case item(ClipboardItem)
        }

        let id: String
        let kind: Kind
    }

    private var pinnedItems: [ClipboardItem] {
        items.filter(\.isPinned)
    }

    private var unpinnedSections: [ItemSection] {
        let unpinnedItems = items.filter { !$0.isPinned }
        guard !unpinnedItems.isEmpty else { return [] }

        var sections: [ItemSection] = []

        for item in unpinnedItems {
            let title = title(for: item.timestamp)

            if let lastIndex = sections.indices.last,
               sections[lastIndex].title == title {
                sections[lastIndex].items.append(item)
            } else {
                sections.append(
                    ItemSection(
                        id: title,
                        title: title,
                        items: [item]
                    )
                )
            }
        }

        return sections
    }

    private var displayRows: [DisplayRow] {
        var rows: [DisplayRow] = []

        if !pinnedItems.isEmpty {
            rows.append(
                DisplayRow(
                    id: "header-pinned",
                    kind: .header(title: "PINNED", systemImage: nil)
                )
            )

            for item in pinnedItems {
                rows.append(
                    DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        for (sectionIndex, section) in unpinnedSections.enumerated() {
            if sectionIndex == 0 && !pinnedItems.isEmpty {
                rows.append(
                    DisplayRow(
                        id: "divider-pinned",
                        kind: .divider
                    )
                )
            }

            rows.append(
                DisplayRow(
                    id: "header-\(section.id)",
                    kind: .header(title: section.title, systemImage: nil)
                )
            )

            for item in section.items {
                rows.append(
                    DisplayRow(
                        id: "item-\(item.id.uuidString)",
                        kind: .item(item)
                    )
                )
            }
        }

        return rows
    }

    var body: some View {
        VStack {
            Spacer(minLength: 3)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    ScrollViewConfigurator { scrollView in
                        scrollView.hasVerticalScroller = false
                        scrollView.autohidesScrollers = true
                        scrollView.scrollerStyle = .overlay

                        scrollView.automaticallyAdjustsContentInsets = false
                        scrollView.verticalScrollElasticity = .none
                        scrollView.horizontalScrollElasticity = .none

                        scrollView.contentInsets = NSEdgeInsets(
                            top: 4,
                            left: 0,
                            bottom: 4,
                            right: 0
                        )

                        scrollController.configure(scrollView: scrollView)
                    }
                    .frame(width: 0, height: 0)

                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id(topScrollAnchorID)

                        ForEach(displayRows) { row in
                            switch row.kind {
                            case .header(let title, let systemImage):
                                sectionHeader(
                                    title,
                                    systemImage: systemImage,
                                    topPadding: row.id == "header-pinned" ? 2 : 6
                                )

                            case .divider:
                                Rectangle()
                                    .fill(Color.primary.opacity(0.12))
                                    .frame(height: 1)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 4)

                            case .item(let item):
                                itemRow(for: item)
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 18)
                }
                .overlay(alignment: .bottom) {
                    scrollToTopButton
                }
                .overlay(alignment: .topTrailing) {
                    customScrollbar
                }
                .onAppear {
                    scrollController.scrollToTop(retryCount: 6)
                }
                .onChange(of: selectedIndex) { newValue in
                    guard scrollTrigger else { return }

                    if let item = items[safe: newValue] {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(item.id)
                        }
                    }

                    scrollTrigger = false

                    DispatchQueue.main.async {
                        scrollController.syncMetrics()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                    scrollController.scrollToTop(retryCount: 6)
                }

                Spacer(minLength: 3)
            }
        }
    }

    @ViewBuilder
    private var scrollToTopButton: some View {
        let viewportHeight = scrollController.viewportHeight
        let scrollOffset = scrollController.scrollOffset

        if scrollOffset > max(80, viewportHeight * 0.35) {
            Button {
                scrollController.scrollToTopImmediately()
            } label: {
                Image(systemName: "arrow.up")
                    .symbolRenderingMode(.monochrome)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .frame(width: 28, height: 28)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)
            .frame(height: 28)
            .bufferGlassSurface(cornerRadius: 14, interactive: true)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var customScrollbar: some View {
        let viewportHeight = scrollController.viewportHeight
        let contentHeight = scrollController.contentHeight

        let trackHeight = max(0, viewportHeight - 8)
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollOffset: scrollController.scrollOffset
            ) { progress in
                scrollController.scroll(to: progress)
            }
            .frame(width: 14, height: trackHeight)
            .contentShape(Rectangle())
            .padding(.trailing, 2)
            .padding(.vertical, 4)
            .zIndex(10)
        }
    }

    private func title(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "TODAY"
        }

        if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        }

        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "THIS WEEK"
        }

        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()),
           calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return "LAST WEEK"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date).uppercased()
    }

    private func sectionHeader(
        _ title: String,
        systemImage: String? = nil,
        topPadding: CGFloat = 6
    ) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }

            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, topPadding)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func itemRow(for item: ClipboardItem) -> some View {
        let index = items.firstIndex(where: { $0.id == item.id }) ?? 0

        return ClipboardItemRow(
            item: item,
            store: store,
            isMultiSelected: selectedIDs.contains(item.id),
            joinsSelectionAbove: index > 0 && selectedIDs.contains(items[index - 1].id),
            joinsSelectionBelow: index < items.count - 1 && selectedIDs.contains(items[index + 1].id),
            quickPasteNumber: showsQuickPasteNumbers && index < 5 ? index + 1 : nil
        )
        .id(item.id)
        .contentShape(Rectangle())
        .overlay(
            ClickModifierDetector { modifiers in
                selectedIndex = index

                if modifiers.hasCommand {
                    onToggleSelection(item.id)
                } else if modifiers.hasShift {
                    onExtendSelectionTo(item.id)
                } else {
                    onSelectSingle(item.id)
                }
            } onHoverChanged: { hovering in
                NotificationCenter.default.post(
                    name: .clipboardRowHoverChanged,
                    object: item.id,
                    userInfo: ["isHovered": hovering]
                )
            },
            alignment: .center
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    // Handled by ClickModifierDetector.
                }
        )
        .highPriorityGesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    selectedIndex = index
                    onSelect(item)
                    onDismiss()
                }
        )
    }
}

private final class ScrollController: ObservableObject {
    @Published private(set) var viewportHeight: CGFloat = 0
    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var scrollOffset: CGFloat = 0

    weak var scrollView: NSScrollView?

    private weak var observedDocumentView: NSView?
    private var observers: [NSObjectProtocol] = []
    private var isMetricsSyncScheduled = false

    deinit {
        removeObservers()
    }

    func configure(scrollView: NSScrollView) {
        let documentViewChanged = observedDocumentView !== scrollView.documentView

        if self.scrollView === scrollView, !documentViewChanged {
            scheduleMetricsSync(from: scrollView)
            return
        }

        removeObservers()

        self.scrollView = scrollView
        observedDocumentView = scrollView.documentView

        startObserving(scrollView: scrollView)
        scheduleMetricsSync(from: scrollView)
    }

    func scroll(to progress: CGFloat) {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return
        }

        let clampedProgress = progress.clamped(to: 0...1)

        let viewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )

        let contentHeight = measuredContentHeight(
            scrollView: scrollView,
            documentView: documentView
        )

        let maxOffset = max(0, contentHeight - viewportHeight)

        // Coordinate model:
        // 0 = visual top
        // maxOffset = visual bottom
        let targetY = maxOffset * clampedProgress

        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: targetY.clamped(to: 0...maxOffset),
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)

        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        syncMetricsNow(from: scrollView)
    }

    func scrollToTop(retryCount: Int = 4) {
        scheduleScrollToTop(remainingPasses: retryCount)
    }

    func scrollToTopImmediately() {
        scrollToTopNow()
    }

    func syncMetrics() {
        guard let scrollView else { return }
        scheduleMetricsSync(from: scrollView)
    }

    private func scheduleScrollToTop(remainingPasses: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.scrollToTopNow()

            if remainingPasses > 0 {
                self.scheduleScrollToTop(remainingPasses: remainingPasses - 1)
            }
        }
    }

    private func scrollToTopNow() {
        guard let scrollView,
              let documentView = scrollView.documentView else {
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let proposedBounds = NSRect(
            x: scrollView.contentView.bounds.minX,
            y: 0,
            width: scrollView.contentView.bounds.width,
            height: scrollView.contentView.bounds.height
        )

        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)

        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        syncMetricsNow(from: scrollView)
    }

    private func startObserving(scrollView: NSScrollView) {
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.scheduleMetricsSync(from: scrollView)
            }
        )

        observers.append(
            center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.scheduleMetricsSync(from: scrollView)
            }
        )

        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            documentView.postsBoundsChangedNotifications = true

            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: documentView,
                    queue: .main
                ) { [weak self, weak scrollView] _ in
                    guard let self, let scrollView else { return }
                    self.scheduleMetricsSync(from: scrollView)
                }
            )
        }
    }

    private func scheduleMetricsSync(from scrollView: NSScrollView) {
        guard !isMetricsSyncScheduled else { return }

        isMetricsSyncScheduled = true

        DispatchQueue.main.async { [weak self, weak scrollView] in
            guard let self else { return }

            self.isMetricsSyncScheduled = false

            guard let scrollView else { return }

            self.syncMetricsNow(from: scrollView)
        }
    }

    private func syncMetricsNow(from scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else {
            update(
                viewportHeight: 0,
                contentHeight: 0,
                scrollOffset: 0
            )
            return
        }

        let nextViewportHeight = max(
            scrollView.contentView.bounds.height,
            scrollView.contentView.frame.height
        )

        let nextContentHeight = measuredContentHeight(
            scrollView: scrollView,
            documentView: documentView
        )

        let maxOffset = max(0, nextContentHeight - nextViewportHeight)
        let rawY = scrollView.contentView.bounds.minY

        // Coordinate model:
        // rawY = 0 means visual top.
        // rawY = maxOffset means visual bottom.
        //
        // Result:
        // scrollOffset = 0 means top.
        // scrollOffset = maxOffset means bottom.
        let nextScrollOffset = rawY.clamped(to: 0...maxOffset)

        update(
            viewportHeight: nextViewportHeight,
            contentHeight: nextContentHeight,
            scrollOffset: nextScrollOffset
        )
    }

    private func measuredContentHeight(
        scrollView: NSScrollView,
        documentView: NSView
    ) -> CGFloat {
        max(
            documentView.bounds.height,
            documentView.frame.height,
            scrollView.contentView.documentRect.height
        )
    }

    private func update(
        viewportHeight nextViewportHeight: CGFloat,
        contentHeight nextContentHeight: CGFloat,
        scrollOffset nextScrollOffset: CGFloat
    ) {
        if abs(viewportHeight - nextViewportHeight) > 0.5 {
            viewportHeight = nextViewportHeight
        }

        if abs(contentHeight - nextContentHeight) > 0.5 {
            contentHeight = nextContentHeight
        }

        if abs(scrollOffset - nextScrollOffset) > 0.5 {
            scrollOffset = nextScrollOffset
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }
}

private struct ScrollViewConfigurator: NSViewRepresentable {
    let configure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.configure = configure
        nsView.scheduleConfiguration()
    }

    final class ConfiguratorView: NSView {
        var configure: ((NSScrollView) -> Void)?

        private var isConfigurationScheduled = false

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
            guard let scrollView = enclosingScrollView else {
                scheduleConfiguration()
                return
            }

            configure?(scrollView)
        }
    }
}

private struct ScrollbarThumbView: NSViewRepresentable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let scrollOffset: CGFloat
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ThumbView {
        let view = ThumbView()
        view.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollOffset: scrollOffset,
            onScroll: onScroll
        )
        return view
    }

    func updateNSView(_ nsView: ThumbView, context: Context) {
        nsView.updateMetrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            scrollOffset: scrollOffset,
            onScroll: onScroll
        )
    }

    final class ThumbView: NSView {
        private var viewportHeight: CGFloat = 0
        private var contentHeight: CGFloat = 0
        private var scrollOffset: CGFloat = 0
        private var onScroll: ((CGFloat) -> Void)?

        private let thumbLayer = CALayer()

        private let collapsedWidth: CGFloat = 5
        private let expandedWidth: CGFloat = 7
        private let animationDuration: CFTimeInterval = 0.14

        private var trackingArea: NSTrackingArea?

        private var isHovering = false
        private var isDraggingThumb = false

        private var dragOffsetWithinThumb: CGFloat = 0
        private var dragProgress: CGFloat?

        private var dragViewportHeight: CGFloat?
        private var dragContentHeight: CGFloat?

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
            thumbLayer.cornerRadius = collapsedWidth / 2
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
            scrollOffset: CGFloat,
            onScroll: @escaping (CGFloat) -> Void
        ) {
            self.onScroll = onScroll

            if !isDraggingThumb {
                self.viewportHeight = viewportHeight
                self.contentHeight = contentHeight
                self.scrollOffset = scrollOffset
                self.dragProgress = nil
                self.dragViewportHeight = nil
                self.dragContentHeight = nil
            }

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
            isHovering = true
            updateThumbLayer(animated: true)
        }

        override func mouseExited(with event: NSEvent) {
            guard !isDraggingThumb else { return }

            isHovering = false
            updateThumbLayer(animated: true)
        }

        override func mouseDown(with event: NSEvent) {
            dragViewportHeight = viewportHeight
            dragContentHeight = contentHeight

            let mouseY = topOriginMouseY(for: event)
            let metrics = scrollbarMetrics()
            let thumbRect = metrics.thumbRect

            guard thumbRect.height > 0 else { return }

            if thumbRect.contains(NSPoint(x: bounds.midX, y: mouseY)) {
                dragOffsetWithinThumb = mouseY - thumbRect.minY
            } else {
                dragOffsetWithinThumb = thumbRect.height / 2

                scroll(
                    toThumbOrigin: mouseY - dragOffsetWithinThumb,
                    metrics: metrics
                )
            }

            isDraggingThumb = true
            updateThumbLayer(animated: true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDraggingThumb else { return }

            let mouseY = topOriginMouseY(for: event)
            let metrics = scrollbarMetrics()

            scroll(
                toThumbOrigin: mouseY - dragOffsetWithinThumb,
                metrics: metrics
            )
        }

        override func mouseUp(with event: NSEvent) {
            isDraggingThumb = false
            dragProgress = nil
            dragViewportHeight = nil
            dragContentHeight = nil

            let mouseY = topOriginMouseY(for: event)
            isHovering = bounds.contains(NSPoint(x: bounds.midX, y: mouseY))

            updateThumbLayer(animated: true)
        }

        private func topOriginMouseY(for event: NSEvent) -> CGFloat {
            let location = convert(event.locationInWindow, from: nil)
            return location.y.clamped(to: 0...bounds.height)
        }

        private func scroll(toThumbOrigin originY: CGFloat, metrics: ScrollbarMetrics) {
            let clampedOrigin = originY.clamped(to: 0...metrics.availableTravel)

            let progress = metrics.availableTravel > 0
                ? clampedOrigin / metrics.availableTravel
                : 0

            let activeViewportHeight = dragViewportHeight ?? viewportHeight
            let activeContentHeight = dragContentHeight ?? contentHeight
            let maxScrollOffset = max(0, activeContentHeight - activeViewportHeight)

            dragProgress = progress
            scrollOffset = maxScrollOffset * progress

            updateThumbLayer(animated: false)
            onScroll?(progress)
        }

        private func updateThumbLayer(animated: Bool) {
            let metrics = scrollbarMetrics()
            let thumbRect = metrics.thumbRect

            guard thumbRect.height > 0 else {
                thumbLayer.isHidden = true
                return
            }

            thumbLayer.isHidden = false

            let visualWidth = isHovering || isDraggingThumb
                ? expandedWidth
                : collapsedWidth

            let alpha: CGFloat

            if isDraggingThumb {
                alpha = 0.46
            } else if isHovering {
                alpha = 0.34
            } else {
                alpha = 0.22
            }

            // CALayer coordinates are bottom-left based.
            // scrollbarMetrics() uses top-origin coordinates.
            let targetFrame = CGRect(
                x: (bounds.width - visualWidth) / 2,
                y: thumbRect.minY,
                width: visualWidth,
                height: thumbRect.height
            )

            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? animationDuration : 0)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(name: .easeInEaseOut)
            )

            thumbLayer.frame = targetFrame
            thumbLayer.cornerRadius = visualWidth / 2
            thumbLayer.backgroundColor = NSColor.labelColor
                .withAlphaComponent(alpha)
                .cgColor

            CATransaction.commit()
        }

        private func scrollbarMetrics() -> ScrollbarMetrics {
            let activeViewportHeight = dragViewportHeight ?? viewportHeight
            let activeContentHeight = dragContentHeight ?? contentHeight

            let trackHeight = bounds.height
            let maxScrollOffset = max(0, activeContentHeight - activeViewportHeight)

            guard trackHeight > 0, maxScrollOffset > 0 else {
                return ScrollbarMetrics(
                    thumbRect: .zero,
                    availableTravel: 0
                )
            }

            let visibleRatio = activeViewportHeight / max(activeContentHeight, activeViewportHeight)
            let thumbHeight = min(trackHeight, max(40, trackHeight * visibleRatio))
            let availableTravel = max(0, trackHeight - thumbHeight)

            let progress: CGFloat

            if let dragProgress {
                progress = dragProgress.clamped(to: 0...1)
            } else {
                progress = maxScrollOffset > 0
                    ? (scrollOffset / maxScrollOffset).clamped(to: 0...1)
                    : 0
            }

            let thumbOrigin = availableTravel * progress

            return ScrollbarMetrics(
                thumbRect: NSRect(
                    x: 0,
                    y: thumbOrigin,
                    width: bounds.width,
                    height: thumbHeight
                ),
                availableTravel: availableTravel
            )
        }
    }
}

private struct ScrollbarMetrics {
    let thumbRect: NSRect
    let availableTravel: CGFloat
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension View {
    @ViewBuilder
    func bufferGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            let baseGlass = Glass.regular.interactive(interactive)
            let configuredGlass = tint.map { baseGlass.tint($0) } ?? baseGlass

            self.glassEffect(
                configuredGlass,
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
        } else {
            self
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}
