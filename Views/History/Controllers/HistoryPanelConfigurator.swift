import Cocoa
import SwiftUI

@MainActor
protocol BufferEffectView: AnyObject {
    func updateBufferAppearance(
        _ appearance: BufferAppearanceConfiguration,
        cornerRadius: CGFloat
    )

    func installBufferContentView(_ contentView: NSView)
}

typealias BufferEffectHostView = NSView & BufferEffectView

enum HistoryWindowStyle {
    static let initialContentSize = NSSize(width: 800, height: 500)
    static let minimumContentSize = NSSize(width: 680, height: 420)
    static let panelCornerRadius = CGFloat(24)
    static let panelBorderOpacity = 0.18
    static let frameAutosaveName = NSWindow.FrameAutosaveName("Buffer.HistoryWindow.Frame")
}

struct HistoryWindowConfiguration: Equatable, Sendable {
    var initialContentSize = HistoryWindowStyle.initialContentSize
    var minimumContentSize = HistoryWindowStyle.minimumContentSize
    var maximumContentSize: NSSize?
    var allowsResizing = true
    var allowsMoving = false
    var frameAutosaveName: NSWindow.FrameAutosaveName? = HistoryWindowStyle.frameAutosaveName
    var paneSplitConfiguration = HistoryPaneSplitConfiguration.standard
    var appearance = BufferAppearanceConfiguration.systemGlass

    static let standard = HistoryWindowConfiguration()
    static let ephemeral = HistoryWindowConfiguration(
        frameAutosaveName: nil,
        paneSplitConfiguration: .ephemeral
    )
}

enum HistoryWindowGeometry {
    static func clampedContentSize(
        _ proposedSize: NSSize,
        fallbackSize: NSSize,
        minimumSize: NSSize,
        maximumSize: NSSize
    ) -> NSSize {
        let safeMaximumSize = NSSize(
            width: max(minimumSize.width, maximumSize.width),
            height: max(minimumSize.height, maximumSize.height)
        )
        let candidate = isValid(proposedSize) ? proposedSize : fallbackSize

        return NSSize(
            width: min(max(candidate.width, minimumSize.width), safeMaximumSize.width),
            height: min(max(candidate.height, minimumSize.height), safeMaximumSize.height)
        )
    }

    private static func isValid(_ size: NSSize) -> Bool {
        size.width.isFinite
            && size.height.isFinite
            && size.width > 0
            && size.height > 0
    }
}

@MainActor
enum HistoryLayoutPersistence {
    static func restoreDefaults(
        for configuration: HistoryWindowConfiguration = .standard,
        defaults: UserDefaults = .standard
    ) {
        if let frameAutosaveName = configuration.frameAutosaveName {
            NSWindow.removeFrame(usingName: frameAutosaveName)
        }

        if let persistenceIdentifier = configuration.paneSplitConfiguration.persistenceIdentifier {
            defaults.removeObject(
                forKey: paneListWidthDefaultsKey(for: persistenceIdentifier)
            )
        }
    }

    static func paneListWidthDefaultsKey(
        for persistenceIdentifier: String
    ) -> String {
        "Buffer.HistoryPaneSplit.ListWidth.\(persistenceIdentifier)"
    }
}

@MainActor
struct HistoryPanelContentConfiguration {
    let containerView: NSView
    let animatedContentView: NSView
    let hostedContentView: NSView
}

@MainActor
struct HistoryPanelConfigurator {
    let configuration: HistoryWindowConfiguration

    init(configuration: HistoryWindowConfiguration = .standard) {
        self.configuration = configuration
    }

    func makePanel() -> HistoryPanel {
        HistoryPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: configuration.initialContentSize.width,
                height: configuration.initialContentSize.height
            ),
            allowsResizing: configuration.allowsResizing
        )
    }

    func configure(_ panel: HistoryPanel) {
        // AppKit resets the level when a panel becomes floating, so set the
        // popup level afterward and keep that ordering covered by tests.
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]

        panel.contentMinSize = configuration.minimumContentSize
        if let maximumContentSize = configuration.maximumContentSize {
            panel.contentMaxSize = maximumContentSize
        }
        panel.appearance = configuration.appearance.mode.appKitAppearance

        panel.isOpaque = false
        panel.backgroundColor = .clear

        panel.isMovable = configuration.allowsMoving
        panel.isMovableByWindowBackground = configuration.allowsMoving
        panel.hasShadow = true

        panel.updateRoundedSurface(cornerRadius: HistoryWindowStyle.panelCornerRadius)

        restoreAndConstrainFrame(of: panel)
        panel.center()

    }

    private func restoreAndConstrainFrame(of panel: HistoryPanel) {
        let restoredFrame: Bool
        if let frameAutosaveName = configuration.frameAutosaveName {
            restoredFrame = panel.setFrameUsingName(frameAutosaveName)
        } else {
            restoredFrame = false
        }

        let proposedSize =
            restoredFrame
            ? panel.contentRect(forFrameRect: panel.frame).size
            : configuration.initialContentSize
        let screenMaximum =
            panel.screen?.visibleFrame.size
            ?? NSScreen.main?.visibleFrame.size
            ?? configuration.maximumContentSize
            ?? proposedSize
        let effectiveMaximum = NSSize(
            width: min(configuration.maximumContentSize?.width ?? screenMaximum.width, screenMaximum.width),
            height: min(
                configuration.maximumContentSize?.height ?? screenMaximum.height,
                screenMaximum.height
            )
        )
        let contentSize = HistoryWindowGeometry.clampedContentSize(
            proposedSize,
            fallbackSize: configuration.initialContentSize,
            minimumSize: configuration.minimumContentSize,
            maximumSize: effectiveMaximum
        )
        panel.setContentSize(contentSize)

        if let frameAutosaveName = configuration.frameAutosaveName {
            panel.setFrameAutosaveName(frameAutosaveName)
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
        containerView.layer?.cornerRadius = HistoryWindowStyle.panelCornerRadius
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true
        containerView.layer?.allowsEdgeAntialiasing = true

        let effectView = makeBufferEffectView(appearance: configuration.appearance)
        effectView.frame = containerView.bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.cornerRadius = HistoryWindowStyle.panelCornerRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.allowsEdgeAntialiasing = true

        let configuredRootView =
            rootView
            .environment(\.bufferAppearance, configuration.appearance)
            .preferredColorScheme(configuration.appearance.mode.colorScheme)
        let hostingView = NSHostingView(rootView: configuredRootView)
        hostingView.frame = effectView.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        effectView.installBufferContentView(hostingView)
        containerView.addSubview(effectView)

        return HistoryPanelContentConfiguration(
            containerView: containerView,
            animatedContentView: effectView,
            hostedContentView: hostingView
        )
    }
}

@available(macOS 26.0, *)
final class BufferLiquidGlassEffectView: NSGlassEffectView, BufferEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .regular
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        style = .regular
        wantsLayer = true
    }

    func updateBufferAppearance(
        _ appearance: BufferAppearanceConfiguration,
        cornerRadius: CGFloat
    ) {
        style = appearance.surfaceStyle == .transparent ? .clear : .regular
        tintColor = appearance.surfaceStyle == .opaque ? .windowBackgroundColor : nil
        self.cornerRadius = cornerRadius
    }

    func installBufferContentView(_ contentView: NSView) {
        self.contentView = contentView
    }
}

final class BufferFrostedGlassEffectView: NSVisualEffectView, BufferEffectView {
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

    func updateBufferAppearance(
        _ appearance: BufferAppearanceConfiguration,
        cornerRadius: CGFloat
    ) {
        switch appearance.surfaceStyle {
        case .glass:
            material =
                NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .hudWindow
                : .popover
        case .transparent:
            material = .underWindowBackground
        case .opaque:
            material = .contentBackground
        }

        updateRoundedCorners(cornerRadius)
    }

    func installBufferContentView(_ contentView: NSView) {
        addSubview(contentView)
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
private func makeBufferEffectView(
    appearance: BufferAppearanceConfiguration
) -> BufferEffectHostView {
    let effectView: BufferEffectHostView
    if #available(macOS 26.0, *),
        appearance.surfaceStyle == .glass,
        appearance.historyWindowMaterial == .liquidGlass
    {
        effectView = BufferLiquidGlassEffectView(frame: .zero)
    } else {
        effectView = BufferFrostedGlassEffectView(frame: .zero)
    }
    effectView.updateBufferAppearance(
        appearance,
        cornerRadius: HistoryWindowStyle.panelCornerRadius
    )
    return effectView
}
