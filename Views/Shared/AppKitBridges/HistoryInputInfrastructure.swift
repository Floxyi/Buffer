import AppKit
import SwiftUI

@MainActor
struct GlobalKeyMonitor: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onJumpToFirst: () -> Void
    let onJumpToLast: () -> Void
    let onExtendToFirst: () -> Void
    let onExtendToLast: () -> Void
    let onExtendUp: () -> Void
    let onExtendDown: () -> Void
    let onEnter: () -> Void
    let onOptionEnter: () -> Void
    let onEscape: () -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onPin: () -> Void
    let onSaveImage: () -> Void
    let onQuickPaste: (Int) -> Void
    let onCommandChanged: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = MonitorHostView()
        view.installMonitor = { [weak coordinator = context.coordinator] window in
            coordinator?.installMonitorIfNeeded(
                window: window,
                onUp: onUp,
                onDown: onDown,
                onJumpToFirst: onJumpToFirst,
                onJumpToLast: onJumpToLast,
                onExtendToFirst: onExtendToFirst,
                onExtendToLast: onExtendToLast,
                onExtendUp: onExtendUp,
                onExtendDown: onExtendDown,
                onEnter: onEnter,
                onOptionEnter: onOptionEnter,
                onEscape: onEscape,
                onDelete: onDelete,
                onCopy: onCopy,
                onPin: onPin,
                onSaveImage: onSaveImage,
                onQuickPaste: onQuickPaste,
                onCommandChanged: onCommandChanged
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    class Coordinator {
        nonisolated(unsafe) var monitor: Any?
        weak var monitoredWindow: NSWindow?

        func installMonitorIfNeeded(
            window: NSWindow?,
            onUp: @escaping () -> Void,
            onDown: @escaping () -> Void,
            onJumpToFirst: @escaping () -> Void,
            onJumpToLast: @escaping () -> Void,
            onExtendToFirst: @escaping () -> Void,
            onExtendToLast: @escaping () -> Void,
            onExtendUp: @escaping () -> Void,
            onExtendDown: @escaping () -> Void,
            onEnter: @escaping () -> Void,
            onOptionEnter: @escaping () -> Void,
            onEscape: @escaping () -> Void,
            onDelete: @escaping () -> Void,
            onCopy: @escaping () -> Void,
            onPin: @escaping () -> Void,
            onSaveImage: @escaping () -> Void,
            onQuickPaste: @escaping (Int) -> Void,
            onCommandChanged: @escaping (NSEvent.ModifierFlags) -> Void
        ) {
            guard monitoredWindow !== window else { return }
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            monitoredWindow = window
            guard let window else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                if event.window !== window {
                    return event
                }

                let relevantFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
                let isCommandOnlyPressed = relevantFlags == .command
                let isCommandShiftOnlyPressed = relevantFlags == [.command, .shift]

                if event.type == .flagsChanged {
                    onCommandChanged(event.modifierFlags)
                    return event
                }

                switch event.keyCode {
                case 126:
                    if isCommandShiftOnlyPressed {
                        onExtendToFirst()
                        return nil
                    }
                    if isCommandOnlyPressed {
                        onJumpToFirst()
                        return nil
                    }
                    event.modifierFlags.contains(.shift) ? onExtendUp() : onUp()
                    return nil
                case 125:
                    if isCommandShiftOnlyPressed {
                        onExtendToLast()
                        return nil
                    }
                    if isCommandOnlyPressed {
                        onJumpToLast()
                        return nil
                    }
                    event.modifierFlags.contains(.shift) ? onExtendDown() : onDown()
                    return nil
                case 36:
                    event.modifierFlags.contains(.option) ? onOptionEnter() : onEnter()
                    return nil
                case 53:
                    onEscape()
                    return nil
                case 51:
                    guard event.modifierFlags.contains(.command) else { return event }
                    onDelete()
                    return nil
                case 8:
                    guard event.modifierFlags.contains(.command) else { return event }
                    if let responder = window.firstResponder, responder is NSTextView {
                        return event
                    }
                    onCopy()
                    return nil
                case 35:
                    guard event.modifierFlags.contains(.command) else { return event }
                    onPin()
                    return nil
                case 1:
                    guard event.modifierFlags.contains(.command) else { return event }
                    onSaveImage()
                    return nil
                case 18...23:
                    guard isCommandOnlyPressed else { return event }
                    let quickPasteIndexByKeyCode: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4]
                    guard let quickPasteIndex = quickPasteIndexByKeyCode[event.keyCode] else { return event }
                    onQuickPaste(quickPasteIndex)
                    return nil
                default:
                    return event
                }
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

@MainActor
private final class MonitorHostView: NSView {
    var installMonitor: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor?(window)
    }
}
