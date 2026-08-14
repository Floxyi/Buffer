import AppKit
import SwiftUI

@MainActor
struct HistoryWindowKeyMonitor: NSViewRepresentable {
    let onCommand: (HistoryKeyboardCommand) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HistoryWindowKeyMonitorHostView()
        view.installMonitor = { [weak coordinator = context.coordinator] window in
            coordinator?.installMonitorIfNeeded(
                window: window,
                onCommand: onCommand
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        nonisolated(unsafe) var monitor: Any?
        weak var monitoredWindow: NSWindow?

        func installMonitorIfNeeded(
            window: NSWindow?,
            onCommand: @escaping (HistoryKeyboardCommand) -> Void
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

                if window.attachedSheet != nil || NSApp.modalWindow?.parent == window {
                    return event
                }

                let focusedTextView = window.firstResponder as? NSTextView
                let command = HistoryKeyboardCommandResolver.resolve(
                    HistoryKeyboardInput(
                        eventType: event.type == .flagsChanged ? .flagsChanged : .keyDown,
                        keyCode: event.keyCode,
                        modifierFlags: event.modifierFlags,
                        isTextInputFocused: focusedTextView != nil,
                        hasTextSelection: focusedTextView?.selectedRange().length ?? 0 > 0
                    )
                )

                guard let command else {
                    return event
                }

                onCommand(command)
                return command == .modifiersChanged(event.modifierFlags) ? event : nil
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
private final class HistoryWindowKeyMonitorHostView: NSView {
    var installMonitor: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitor?(window)
    }
}
