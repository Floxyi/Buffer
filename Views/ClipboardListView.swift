import SwiftUI
import AppKit

/// Vertical list of clipboard items with keyboard navigation
struct ClipboardListView: View {
    private let topScrollAnchorID = "history-list-top"
    private let calendar = Calendar.current
    private let scrollCoordinateSpaceName = "history-list-scroll"
    private let scrollIndicatorGutter: CGFloat = 10
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
    
    @State private var lastClickedItemID: UUID?
    @State private var lastClickGesture: ClickType = .single
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    
    enum ClickType {
        case single
        case shiftClick
        case cmdClick
    }

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
            if let lastIndex = sections.indices.last, sections[lastIndex].title == title {
                sections[lastIndex].items.append(item)
            } else {
                sections.append(ItemSection(id: title, title: title, items: [item]))
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
                rows.append(DisplayRow(id: "item-\(item.id.uuidString)", kind: .item(item)))
            }
        }

        for (sectionIndex, section) in unpinnedSections.enumerated() {
            if sectionIndex == 0 && !pinnedItems.isEmpty {
                rows.append(DisplayRow(id: "divider-pinned", kind: .divider))
            }

            rows.append(
                DisplayRow(
                    id: "header-\(section.id)",
                    kind: .header(title: section.title, systemImage: nil)
                )
            )

            for item in section.items {
                rows.append(DisplayRow(id: "item-\(item.id.uuidString)", kind: .item(item)))
            }
        }

        return rows
    }
    
    var body: some View {
        VStack {
            Spacer(minLength: 3)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        Color.clear
                            .frame(height: 0)
                            .id(topScrollAnchorID)

                        ForEach(displayRows) { row in
                            switch row.kind {
                            case .header(let title, let systemImage):
                                sectionHeader(title, systemImage: systemImage)
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
                    .padding(.leading, 4)
                    .padding(.trailing, scrollIndicatorGutter)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollMetricsPreferenceKey.self,
                                value: ScrollMetrics(
                                    viewportHeight: nil,
                                    contentHeight: geometry.size.height,
                                    contentMinY: geometry.frame(in: .named(scrollCoordinateSpaceName)).minY
                                )
                            )
                        }
                    )
                }
                .coordinateSpace(name: scrollCoordinateSpaceName)
                .background(
                    ScrollViewConfigurator { scrollView in
                        scrollView.hasVerticalScroller = false
                        scrollView.scrollerStyle = .overlay
                        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
                        scrollController.configure(scrollView: scrollView)
                    }
                )
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ScrollMetricsPreferenceKey.self,
                            value: ScrollMetrics(
                                viewportHeight: geometry.size.height,
                                contentHeight: nil,
                                contentMinY: nil
                            )
                        )
                    }
                )
                .onPreferenceChange(ScrollMetricsPreferenceKey.self) { metrics in
                    if let viewportHeight = metrics.viewportHeight {
                        self.viewportHeight = viewportHeight
                    }

                    if let contentHeight = metrics.contentHeight {
                        self.contentHeight = contentHeight
                    }

                    if let contentMinY = metrics.contentMinY {
                        scrollOffset = max(0, -contentMinY)
                    }
                }
                .overlay(alignment: .bottom) {
                    scrollToTopButton(proxy: proxy)
                }
                .overlay(alignment: .topTrailing) {
                    customScrollbar
                }
                .onChange(of: selectedIndex) { newValue in
                    // Only scroll if triggered by keyboard
                    if scrollTrigger {
                        if let item = items[safe: newValue] {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                // No anchor means minimal scrolling (just enough to make visible)
                                proxy.scrollTo(item.id)
                            }
                        }
                        scrollTrigger = false
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .bufferWindowDidOpen)) { _ in
                    // Always snap to the top when the window is reopened
                    proxy.scrollTo(topScrollAnchorID, anchor: .top)
                }

                Spacer(minLength: 3)
            }
        }
    }

    @ViewBuilder
    private func scrollToTopButton(proxy: ScrollViewProxy) -> some View {
        if scrollOffset > max(80, viewportHeight * 0.35) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(topScrollAnchorID, anchor: .top)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .symbolRenderingMode(.monochrome)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        let trackHeight = max(0, viewportHeight - 8)
        let maxScrollOffset = max(0, contentHeight - viewportHeight)

        if trackHeight > 0, maxScrollOffset > 0 {
            ScrollbarThumbView(
                viewportHeight: viewportHeight,
                contentHeight: contentHeight,
                scrollOffset: scrollOffset
            ) { progress in
                scrollController.scroll(to: progress)
            }
                .frame(width: 5, height: trackHeight)
                .padding(.trailing, 2)
                .padding(.vertical, 4)
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

    private func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
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
            },
            alignment: .center
        )
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in
                    // This will be handled by ClickModifierDetector
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
    weak var scrollView: NSScrollView?

    func scroll(to progress: CGFloat) {
        guard let scrollView,
              let documentView = scrollView.documentView else { return }

        let clampedProgress = min(max(progress, 0), 1)
        let viewportHeight = scrollView.contentView.bounds.height
        let contentHeight = documentView.bounds.height
        let maxOffset = max(0, contentHeight - viewportHeight)
        let targetOffset = maxOffset * clampedProgress

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func configure(scrollView: NSScrollView) {
        self.scrollView = scrollView
    }
}

private struct ScrollViewConfigurator: NSViewRepresentable {
    let configure: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguratorView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ConfiguratorView {
            view.configure = configure
            view.applyConfigurationIfNeeded()
        }
    }

    private final class ConfiguratorView: NSView {
        var configure: ((NSScrollView) -> Void)?
        private weak var configuredScrollView: NSScrollView?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyConfigurationIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyConfigurationIfNeeded()
        }

        func applyConfigurationIfNeeded() {
            guard let scrollView = enclosingScrollView else { return }
            configure?(scrollView)
            configuredScrollView = scrollView
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
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ThumbView, context: Context) {
        nsView.viewportHeight = viewportHeight
        nsView.contentHeight = contentHeight
        nsView.scrollOffset = scrollOffset
        nsView.onScroll = onScroll
        nsView.needsDisplay = true
    }

    final class ThumbView: NSView {
        var viewportHeight: CGFloat = 0
        var contentHeight: CGFloat = 0
        var scrollOffset: CGFloat = 0
        var onScroll: ((CGFloat) -> Void)?

        private var trackingArea: NSTrackingArea?
        private var isHovering = false {
            didSet { needsDisplay = true }
        }
        private var dragOffsetWithinThumb: CGFloat = 0
        private var isDraggingThumb = false {
            didSet { needsDisplay = true }
        }

        override var isFlipped: Bool {
            true
        }

        override var mouseDownCanMoveWindow: Bool {
            false
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            isDraggingThumb = false
        }

        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow, from: nil)
            let metrics = scrollbarMetrics()
            let thumbRect = metrics.thumbRect

            if thumbRect.contains(location) {
                dragOffsetWithinThumb = location.y - thumbRect.minY
            } else {
                dragOffsetWithinThumb = thumbRect.height / 2
                scroll(toThumbOrigin: location.y - dragOffsetWithinThumb, metrics: metrics)
            }

            isDraggingThumb = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDraggingThumb else { return }

            let location = convert(event.locationInWindow, from: nil)
            scroll(toThumbOrigin: location.y - dragOffsetWithinThumb, metrics: scrollbarMetrics())
        }

        override func mouseUp(with event: NSEvent) {
            isDraggingThumb = false
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.clear.setFill()
            dirtyRect.fill()

            let thumbRect = scrollbarMetrics().thumbRect
            guard thumbRect.height > 0 else { return }

            let alpha: CGFloat
            if isDraggingThumb {
                alpha = 0.46
            } else if isHovering {
                alpha = 0.34
            } else {
                alpha = 0.22
            }

            NSColor.labelColor.withAlphaComponent(alpha).setFill()
            NSBezierPath(
                roundedRect: thumbRect,
                xRadius: thumbRect.width / 2,
                yRadius: thumbRect.width / 2
            ).fill()
        }

        private func scroll(toThumbOrigin originY: CGFloat, metrics: ScrollbarMetrics) {
            let clampedOrigin = originY.clamped(to: 0...metrics.availableTravel)
            let progress = metrics.availableTravel > 0 ? clampedOrigin / metrics.availableTravel : 0
            onScroll?(progress)
        }

        private func scrollbarMetrics() -> ScrollbarMetrics {
            let trackHeight = bounds.height
            let maxScrollOffset = max(0, contentHeight - viewportHeight)
            let visibleRatio = viewportHeight / max(contentHeight, viewportHeight)
            let thumbHeight = max(40, trackHeight * visibleRatio)
            let availableTravel = max(0, trackHeight - thumbHeight)
            let progress = maxScrollOffset > 0 ? (scrollOffset / maxScrollOffset).clamped(to: 0...1) : 0
            let thumbOrigin = availableTravel * progress
            return ScrollbarMetrics(
                thumbRect: NSRect(x: 0, y: thumbOrigin, width: bounds.width, height: thumbHeight),
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
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
        }
    }
}

private struct ScrollMetrics: Equatable {
    var viewportHeight: CGFloat?
    var contentHeight: CGFloat?
    var contentMinY: CGFloat?
}

private struct ScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()

    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()

        if let viewportHeight = next.viewportHeight {
            value.viewportHeight = viewportHeight
        }

        if let contentHeight = next.contentHeight {
            value.contentHeight = contentHeight
        }

        if let contentMinY = next.contentMinY {
            value.contentMinY = contentMinY
        }
    }
}
