import Cocoa
import SwiftUI

@MainActor
protocol BufferEffectView: AnyObject {
    func updateBufferAppearance(cornerRadius: CGFloat)
}

typealias BufferEffectHostView = NSView & BufferEffectView

enum HistoryWindowStyle {
    static let panelSize = NSSize(width: 800, height: 500)
    static let panelCornerRadius = CGFloat(24)
    static let panelBorderOpacity = 0.18
}

@MainActor
struct HistoryPanelContentConfiguration {
    let containerView: NSView
    let animatedContentView: NSView
}

@MainActor
struct HistoryPanelConfigurator {
    func makePanel() -> HistoryPanel {
        HistoryPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HistoryWindowStyle.panelSize.width,
                height: HistoryWindowStyle.panelSize.height
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }

    func configure(
        _ panel: NSPanel,
        onDidBecomeKey: @escaping @MainActor @Sendable () -> Void
    ) -> NSObjectProtocol {
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        panel.setContentSize(HistoryWindowStyle.panelSize)
        panel.minSize = HistoryWindowStyle.panelSize
        panel.maxSize = HistoryWindowStyle.panelSize

        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear

        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true

        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = HistoryWindowStyle.panelCornerRadius
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        panel.center()

        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        return NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor in
                onDidBecomeKey()
            }
        }
    }

    func makeContentConfiguration<Content: View>(
        rootView: Content,
        frame: NSRect
    ) -> HistoryPanelContentConfiguration {
        let containerView = NSView(frame: frame)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.masksToBounds = false

        let effectView = makeBufferEffectView()
        effectView.frame = containerView.bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.cornerRadius = HistoryWindowStyle.panelCornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.allowsEdgeAntialiasing = true

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        effectView.addSubview(hostingView)
        containerView.addSubview(effectView)

        return HistoryPanelContentConfiguration(
            containerView: containerView,
            animatedContentView: effectView
        )
    }
}

private final class BufferFrostedGlassEffectView: NSVisualEffectView, BufferEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        blendingMode = .behindWindow
        state = .active
        material = .hudWindow
        wantsLayer = true
    }

    func updateBufferAppearance(cornerRadius: CGFloat) {
        material = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .hudWindow
            : .popover

        updateRoundedCorners(cornerRadius)
    }

    private func updateRoundedCorners(_ cornerRadius: CGFloat) {
        guard cornerRadius > 0 else {
            maskImage = nil
            return
        }

        let edgeLength = 2.0 * cornerRadius + 1.0
        let mask = NSImage(
            size: NSSize(width: edgeLength, height: edgeLength),
            flipped: false
        ) { rect in
            NSColor.black.set()
            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
            return true
        }

        mask.capInsets = NSEdgeInsets(
            top: cornerRadius,
            left: cornerRadius,
            bottom: cornerRadius,
            right: cornerRadius
        )
        mask.resizingMode = .stretch
        maskImage = mask
    }
}

@MainActor
private func makeBufferEffectView() -> BufferEffectHostView {
    let effectView = BufferFrostedGlassEffectView(frame: .zero)
    effectView.updateBufferAppearance(cornerRadius: HistoryWindowStyle.panelCornerRadius)
    return effectView
}
