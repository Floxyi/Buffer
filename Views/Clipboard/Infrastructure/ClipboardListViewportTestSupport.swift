#if DEBUG
    import AppKit
    import SwiftUI

    /// Debug-only row instrumentation used by the in-process viewport tests.
    /// Release builds do not install tracking views in list rows.
    @MainActor
    final class ClipboardListViewportProbe {
        private final class WeakTrackingView {
            weak var value: ClipboardListViewportTrackingView?

            init(_ value: ClipboardListViewportTrackingView) {
                self.value = value
            }
        }

        private var viewsByItemID: [UUID: WeakTrackingView] = [:]

        func register(_ view: ClipboardListViewportTrackingView) {
            viewsByItemID[view.itemID] = WeakTrackingView(view)
            view.viewportProbe = self
        }

        func unregister(_ view: ClipboardListViewportTrackingView) {
            if viewsByItemID[view.itemID]?.value === view {
                viewsByItemID.removeValue(forKey: view.itemID)
            }
            view.viewportProbe = nil
        }
    }

    private struct ClipboardListViewportProbeKey: EnvironmentKey {
        static let defaultValue: ClipboardListViewportProbe? = nil
    }

    extension EnvironmentValues {
        var clipboardListViewportProbe: ClipboardListViewportProbe? {
            get { self[ClipboardListViewportProbeKey.self] }
            set { self[ClipboardListViewportProbeKey.self] = newValue }
        }
    }

    @MainActor
    final class ClipboardListViewportTrackingView: NSView {
        var itemID: UUID
        weak var viewportProbe: ClipboardListViewportProbe?

        init(itemID: UUID) {
            self.itemID = itemID
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func frameInViewport() -> CGRect? {
            guard let clipView = enclosingClipView else { return nil }
            let frameInClipCoordinates = convert(bounds, to: clipView)
            return frameInClipCoordinates.offsetBy(
                dx: -clipView.bounds.minX,
                dy: -clipView.bounds.minY
            )
        }

        private var enclosingClipView: NSClipView? {
            var candidate = superview
            while let view = candidate {
                if let clipView = view as? NSClipView {
                    return clipView
                }
                candidate = view.superview
            }
            return nil
        }
    }

    struct ClipboardListViewportRowTracker: NSViewRepresentable {
        let itemID: UUID
        let viewportProbe: ClipboardListViewportProbe

        func makeNSView(context: Context) -> ClipboardListViewportTrackingView {
            let view = ClipboardListViewportTrackingView(itemID: itemID)
            viewportProbe.register(view)
            return view
        }

        func updateNSView(_ view: ClipboardListViewportTrackingView, context: Context) {
            if view.itemID != itemID {
                viewportProbe.unregister(view)
            }
            view.itemID = itemID
            viewportProbe.register(view)
        }

        static func dismantleNSView(
            _ view: ClipboardListViewportTrackingView,
            coordinator: Void
        ) {
            view.viewportProbe?.unregister(view)
        }
    }
#endif
