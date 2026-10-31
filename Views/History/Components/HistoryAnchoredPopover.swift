import AppKit
import QuartzCore
import SwiftUI

private enum HistoryPopoverMotion {
    static let openDuration: TimeInterval = 0.15
    static let closeDuration: TimeInterval = 0.11
    static let reduceMotionOpenDuration: TimeInterval = 0.07
    static let reduceMotionCloseDuration: TimeInterval = 0.06
}

/// Presents native AppKit popovers with a small, controlled window transition.
///
/// The system animation currently opens a nested Core Animation transaction
/// during commit on macOS 27. Keeping `NSPopover.animates` disabled avoids that
/// invalid transaction. The popover window itself supplies the lightweight,
/// Reduce-Motion-aware transition, so its material, border, and arrow move as
/// one surface. Arrow placement, dismissal, and accessibility remain owned by
/// AppKit.
struct HistoryAnchoredPopover<Content: View>: NSViewRepresentable {
    @Environment(\.bufferAppearance) private var appearance

    @Binding private var isPresented: Bool
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.content = content()
    }

    func makeCoordinator() -> HistoryAnchoredPopoverCoordinator {
        HistoryAnchoredPopoverCoordinator()
    }

    func makeNSView(context: Context) -> HistoryPopoverAnchorView {
        HistoryPopoverAnchorView(frame: .zero)
    }

    func updateNSView(_ anchorView: HistoryPopoverAnchorView, context: Context) {
        let hostedContent = AnyView(
            content
                .environment(\.bufferAppearance, appearance)
                .preferredColorScheme(appearance.mode.colorScheme)
        )
        context.coordinator.update(
            isPresented: $isPresented,
            content: hostedContent,
            anchorView: anchorView
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: HistoryPopoverAnchorView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: max(0, width), height: max(0, height))
    }

    static func dismantleNSView(
        _ nsView: HistoryPopoverAnchorView,
        coordinator: HistoryAnchoredPopoverCoordinator
    ) {
        coordinator.invalidate()
    }
}

@MainActor
final class HistoryAnchoredPopoverCoordinator: NSObject, NSPopoverDelegate {
    // Keep the controller's initial fitting size finite until the real content
    // replaces this placeholder before presentation.
    private let hostingController = NSHostingController(
        rootView: AnyView(Color.clear.frame(width: 1, height: 1))
    )
    private let popover = NSPopover()
    private var isPresented: Binding<Bool>?
    private weak var anchorView: NSView?
    private var requestedPresentation = false
    private var presentationGeneration = 0
    private var localEventMonitor: Any?

    override init() {
        super.init()
        hostingController.sizingOptions = [.preferredContentSize]
        hostingController.preferredContentSize = NSSize(width: 1, height: 1)
        // A transient popover closes on the trigger's mouse-down before
        // SwiftUI receives the button action on mouse-up. The action then
        // observes `false` and immediately reopens it. Owning dismissal
        // keeps trigger toggles deterministic while retaining native
        // outside-click and Escape behavior.
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 1, height: 1)
        popover.contentViewController = hostingController
        popover.delegate = self
    }

    func update(
        isPresented: Binding<Bool>,
        content: AnyView,
        anchorView: NSView
    ) {
        self.isPresented = isPresented
        self.anchorView = anchorView
        hostingController.rootView = content

        let shouldPresent = isPresented.wrappedValue
        guard shouldPresent != requestedPresentation else { return }
        requestedPresentation = shouldPresent
        presentationGeneration &+= 1
        let generation = presentationGeneration

        if shouldPresent {
            guard !popover.isShown else {
                animatePopoverOpen(generation: generation, isInitialPresentation: false)
                return
            }
            Task { @MainActor [weak self, weak anchorView] in
                await Task.yield()
                guard let self, let anchorView else { return }
                guard self.presentationGeneration == generation else { return }
                guard self.isPresented?.wrappedValue == true else { return }
                guard anchorView.window != nil, !anchorView.bounds.isEmpty else { return }

                self.popover.show(
                    relativeTo: anchorView.bounds,
                    of: anchorView,
                    preferredEdge: .minY
                )
                self.installDismissalHandling()
                self.animatePopoverOpen(
                    generation: generation,
                    isInitialPresentation: true
                )
            }
        } else if popover.isShown {
            beginAnimatedClose(generation: generation)
        }
    }

    func invalidate() {
        presentationGeneration &+= 1
        requestedPresentation = false
        removeDismissalHandling()
        isPresented = nil
        anchorView = nil
        popover.delegate = nil
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        requestedPresentation = false
        removeDismissalHandling()
        guard isPresented?.wrappedValue == true else { return }
        isPresented?.wrappedValue = false
    }

    private func installDismissalHandling() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalEvent(event)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func removeDismissalHandling() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown, event.keyCode == 53 {
            dismiss()
            return nil
        }

        guard
            event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown
        else {
            return event
        }

        if event.window === hostingController.view.window {
            return event
        }

        // Leave the popover open through mouse-down so the trigger button
        // can turn its binding off on mouse-up. This avoids close/reopen
        // flicker and makes a second trigger click a true toggle.
        if event.type == .leftMouseDown, eventIsInsideAnchor(event) {
            return event
        }

        dismiss()
        return event
    }

    private func eventIsInsideAnchor(_ event: NSEvent) -> Bool {
        guard let anchorView, event.window === anchorView.window else { return false }
        let location = anchorView.convert(event.locationInWindow, from: nil)
        return anchorView.bounds.contains(location)
    }

    private func dismiss() {
        guard popover.isShown || isPresented?.wrappedValue == true else { return }
        isPresented?.wrappedValue = false
        requestedPresentation = false
        presentationGeneration &+= 1
        beginAnimatedClose(generation: presentationGeneration)
    }

    private func animatePopoverOpen(
        generation: Int,
        isInitialPresentation: Bool
    ) {
        guard presentationGeneration == generation else { return }
        guard requestedPresentation, isPresented?.wrappedValue == true else { return }
        guard let window = hostingController.view.window else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if isInitialPresentation {
            window.alphaValue = 0
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration =
                reduceMotion
                ? HistoryPopoverMotion.reduceMotionOpenDuration
                : HistoryPopoverMotion.openDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
        }
    }

    private func beginAnimatedClose(generation: Int) {
        guard popover.isShown else { return }
        guard let window = hostingController.view.window else {
            finishClose(generation: generation, window: nil)
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration =
                    reduceMotion
                    ? HistoryPopoverMotion.reduceMotionCloseDuration
                    : HistoryPopoverMotion.closeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                context.allowsImplicitAnimation = true
                window.animator().alphaValue = 0
            },
            completionHandler: { [weak self, weak window] in
                Task { @MainActor in
                    self?.finishClose(generation: generation, window: window)
                }
            }
        )
    }

    private func finishClose(generation: Int, window: NSWindow?) {
        guard presentationGeneration == generation else { return }
        guard !requestedPresentation, isPresented?.wrappedValue != true else { return }
        popover.close()
        window?.alphaValue = 1
    }

    @objc
    private func applicationDidResignActive(_ notification: Notification) {
        dismiss()
    }
}

final class HistoryPopoverAnchorView: NSView {
    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
