import SwiftUI
import AppKit

/// A simple wrapper that detects clicks with modifier keys
struct ClickModifierDetector: NSViewRepresentable {
    let onClickWithModifiers: (NSEvent.ModifierFlags) -> Void
    var onHoverChanged: ((Bool) -> Void)? = nil
    
    class ClickView: NSView {
        var onClickWithModifiers: ((NSEvent.ModifierFlags) -> Void)?
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }
        
        override func mouseDown(with event: NSEvent) {
            onClickWithModifiers?(event.modifierFlags)
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = ClickView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.onClickWithModifiers = onClickWithModifiers
        view.onHoverChanged = onHoverChanged
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let clickView = nsView as? ClickView {
            clickView.onClickWithModifiers = onClickWithModifiers
            clickView.onHoverChanged = onHoverChanged
        }
    }
}

// MARK: - Modifier Flags Extension
extension NSEvent.ModifierFlags {
    var hasCommand: Bool {
        self.contains(.command)
    }
    
    var hasShift: Bool {
        self.contains(.shift)
    }
}
