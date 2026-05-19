import Cocoa
import SwiftUI
import QuartzCore

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
private enum HistoryWindowAnimation {
    static let openDuration: CFTimeInterval = 0.20
    static let fadeDuration: CFTimeInterval = 0.12
    static let openStartScale: CGFloat = 0.965
    static let openStartOpacity: Float = 0

    static func makeScaleTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: 0.18,
            0.82,
            0.22,
            1.0
        )
    }

    static func makeFadeTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeOut)
    }
}

private enum HistoryWindowAnimationKey {
    static let scale = "buffer.history.open.scale"
    static let opacity = "buffer.history.open.opacity"
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

@MainActor
final class HistoryPanel: NSPanel {
    var onClickOutside: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onClickOutside?()
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    private let store: ClipboardStore
    private let settingsManager: SettingsManager
    private let activeApplicationProvider: ActiveApplicationProviding
    private let pasteController: PasteControlling
    private let ignoreNextCapturedChange: @MainActor () -> Void

    private var previousApp: NSRunningApplication?
    nonisolated(unsafe) private var keyObserver: NSObjectProtocol?

    private let viewModel: HistoryViewModel
    private var focusSearchOnNextOpen = true
    private var suppressQuickPasteUntilModifiersReleasedOnNextOpen = false
    private var shouldIgnoreNextDidBecomeKeyOpenHandling = false
    private var animationGeneration = 0
    // Reopen scroll restoration is window-owned because the live NSScrollView lifecycle
    // does not align cleanly with view-model updates during close/open transitions.
    private var lastListScrollOffset = CGFloat.zero
    private var pendingListScrollOffsetRestore: CGFloat?
    private var listScrollOffsetProvider: (() -> CGFloat)?
    private var listScrollOffsetRestorer: ((CGFloat) -> Void)?

    private weak var animatedContentView: NSView?

    init(
        store: ClipboardStore,
        settingsManager: SettingsManager,
        activeApplicationProvider: ActiveApplicationProviding,
        pasteController: PasteControlling,
        ocrService: OCRServicing,
        ignoreNextCapturedChange: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.settingsManager = settingsManager
        self.activeApplicationProvider = activeApplicationProvider
        self.pasteController = pasteController
        self.ignoreNextCapturedChange = ignoreNextCapturedChange
        self.viewModel = HistoryViewModel(
            store: store,
            settingsManager: settingsManager,
            ocrService: ocrService
        )

        let panel = HistoryPanel(
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

        super.init(window: panel)

        panel.onClickOutside = { [weak self] in
            self?.close()
        }

        setupPanel(panel)
        setupContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        showWindow(
            sender,
            focusSearch: true,
            activateApp: true,
            suppressQuickPasteUntilModifiersReleased: false
        )
    }

    func showWindow(
        _ sender: Any?,
        focusSearch: Bool,
        activateApp: Bool,
        suppressQuickPasteUntilModifiersReleased: Bool
    ) {
        focusSearchOnNextOpen = focusSearch
        suppressQuickPasteUntilModifiersReleasedOnNextOpen = suppressQuickPasteUntilModifiersReleased
        previousApp = activeApplicationProvider.currentApplication

        guard let window else {
            return
        }

        animationGeneration += 1
        let currentAnimationGeneration = animationGeneration
        let shouldAnimate = !window.isVisible

        window.center()

        shouldIgnoreNextDidBecomeKeyOpenHandling = true
        viewModel.handleWindowOpen(
            focusSearch: focusSearchOnNextOpen,
            suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleasedOnNextOpen
        )

        if shouldAnimate {
            prepareOpenAnimationState()
        } else {
            resetOpenAnimationState()
        }

        super.showWindow(sender)

        if activateApp {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }

        window.makeKeyAndOrderFront(nil)
        window.makeMain()

        if settingsManager.keepHistoryWindowSelectionOnReopen {
            restoreLastListScrollOffsetIfPossible()
        }

        if shouldAnimate {
            animateOpen(generation: currentAnimationGeneration)
        }
    }

    override func close() {
        animationGeneration += 1
        resetOpenAnimationState()
        lastListScrollOffset = max(0, listScrollOffsetProvider?() ?? lastListScrollOffset)
        super.close()
    }

    private func setupPanel(_ panel: NSPanel) {
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

        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePanelDidBecomeKey()
            }
        }
    }

    private func setupContent() {
        let rootView = HistoryContentView(
            viewModel: viewModel,
            settings: settingsManager,
            store: store,
            onCopyToClipboard: { [weak self] item in
                self?.copyToClipboard(item)
            },
            onCopyMultipleToClipboard: { [weak self] items in
                self?.copyToClipboard(items)
            },
            onPaste: { [weak self] item in
                self?.pasteItem(item)
            },
            onPasteMultiple: { [weak self] items in
                self?.pasteMultiple(items)
            },
            onScrollOffsetProviderChanged: { [weak self] provider in
                self?.setListScrollOffsetProvider(provider)
            },
            onScrollOffsetRestorerChanged: { [weak self] restorer in
                self?.setListScrollOffsetRestorer(restorer)
            },
            onDismiss: { [weak self] in
                self?.close()
            }
        )

        let containerView = NSView(frame: window?.contentView?.bounds ?? .zero)
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

        animatedContentView = effectView
        window?.contentView = containerView
    }

    private func prepareOpenAnimationState() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetOpenAnimationState()
            return
        }

        guard let layer = prepareAnimatedContentLayer() else {
            return
        }

        performWithoutLayerActions {
            layer.removeAnimation(forKey: HistoryWindowAnimationKey.scale)
            layer.removeAnimation(forKey: HistoryWindowAnimationKey.opacity)

            layer.transform = CATransform3DMakeScale(
                HistoryWindowAnimation.openStartScale,
                HistoryWindowAnimation.openStartScale,
                1
            )

            layer.opacity = HistoryWindowAnimation.openStartOpacity
        }
    }

    private func animateOpen(generation: Int) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetOpenAnimationState()
            return
        }

        guard let layer = prepareAnimatedContentLayer() else {
            return
        }

        performWithoutLayerActions {
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
        }

        let scaleAnimation = CABasicAnimation(keyPath: "transform")
        scaleAnimation.fromValue = NSValue(
            caTransform3D: CATransform3DMakeScale(
                HistoryWindowAnimation.openStartScale,
                HistoryWindowAnimation.openStartScale,
                1
            )
        )
        scaleAnimation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        scaleAnimation.duration = HistoryWindowAnimation.openDuration
        scaleAnimation.timingFunction = HistoryWindowAnimation.makeScaleTimingFunction()
        scaleAnimation.isRemovedOnCompletion = true

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = HistoryWindowAnimation.openStartOpacity
        opacityAnimation.toValue = 1
        opacityAnimation.duration = HistoryWindowAnimation.fadeDuration
        opacityAnimation.timingFunction = HistoryWindowAnimation.makeFadeTimingFunction()
        opacityAnimation.isRemovedOnCompletion = true

        layer.add(scaleAnimation, forKey: HistoryWindowAnimationKey.scale)
        layer.add(opacityAnimation, forKey: HistoryWindowAnimationKey.opacity)

        Task { @MainActor [weak self] in
            let delay = UInt64(HistoryWindowAnimation.openDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            guard let self else {
                return
            }

            guard self.animationGeneration == generation, self.window?.isVisible == true else {
                return
            }

            self.resetOpenAnimationState()
        }
    }

    private func resetOpenAnimationState() {
        guard let layer = prepareAnimatedContentLayer() else {
            window?.alphaValue = 1
            return
        }

        performWithoutLayerActions {
            layer.removeAnimation(forKey: HistoryWindowAnimationKey.scale)
            layer.removeAnimation(forKey: HistoryWindowAnimationKey.opacity)
            layer.transform = CATransform3DIdentity
            layer.opacity = 1
        }

        window?.alphaValue = 1
    }

    private func prepareAnimatedContentLayer() -> CALayer? {
        guard let animatedContentView else {
            return nil
        }

        animatedContentView.superview?.layoutSubtreeIfNeeded()
        animatedContentView.layoutSubtreeIfNeeded()
        animatedContentView.wantsLayer = true

        guard let layer = animatedContentView.layer else {
            return nil
        }

        performWithoutLayerActions {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(
                x: animatedContentView.frame.midX,
                y: animatedContentView.frame.midY
            )
            layer.allowsEdgeAntialiasing = true
            layer.masksToBounds = true
        }

        return layer
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    private func handlePanelDidBecomeKey() {
        if shouldIgnoreNextDidBecomeKeyOpenHandling {
            shouldIgnoreNextDidBecomeKeyOpenHandling = false
            return
        }

        viewModel.handleWindowOpen(
            focusSearch: focusSearchOnNextOpen,
            suppressQuickPasteUntilModifiersReleased: suppressQuickPasteUntilModifiersReleasedOnNextOpen
        )

        if settingsManager.keepHistoryWindowSelectionOnReopen {
            restoreLastListScrollOffsetIfPossible()
        }
    }

    private func restoreLastListScrollOffsetIfPossible() {
        guard settingsManager.keepHistoryWindowSelectionOnReopen else {
            pendingListScrollOffsetRestore = nil
            return
        }

        let offset = max(0, lastListScrollOffset)
        guard offset > 0.5 else {
            pendingListScrollOffsetRestore = nil
            return
        }

        if let listScrollOffsetRestorer {
            pendingListScrollOffsetRestore = nil
            listScrollOffsetRestorer(offset)
        } else {
            pendingListScrollOffsetRestore = offset
        }
    }

    private func setListScrollOffsetProvider(_ provider: (() -> CGFloat)?) {
        listScrollOffsetProvider = provider
    }

    private func setListScrollOffsetRestorer(_ restorer: ((CGFloat) -> Void)?) {
        listScrollOffsetRestorer = restorer

        guard let restorer, let pendingListScrollOffsetRestore else {
            return
        }

        self.pendingListScrollOffsetRestore = nil
        restorer(pendingListScrollOffsetRestore)
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        ignoreNextCapturedChange()
        pasteController.copyToClipboard(item)
    }

    private func copyToClipboard(_ items: [ClipboardItem]) {
        ignoreNextCapturedChange()
        pasteController.copyMultipleToClipboard(items)
    }

    private func pasteItem(_ item: ClipboardItem) {
        let appToRestore = previousApp

        close()

        pasteController.paste(
            item,
            previousApp: appToRestore,
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }

    private func pasteMultiple(_ items: [ClipboardItem]) {
        let appToRestore = previousApp

        close()

        pasteController.pasteMultiple(
            items,
            previousApp: appToRestore,
            ignoreNextCapturedChange: ignoreNextCapturedChange
        )
    }
}
