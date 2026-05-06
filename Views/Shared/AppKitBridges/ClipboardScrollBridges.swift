import AppKit
import SwiftUI

struct ScrollViewConfigurator: NSViewRepresentable {
    enum SearchStrategy {
        case nearestAncestorOnly
        case nearestOrFallback
    }

    let configure: (NSScrollView) -> Void
    var searchStrategy: SearchStrategy = .nearestOrFallback

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.configure = configure
        view.searchStrategy = searchStrategy
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.configure = configure
        nsView.searchStrategy = searchStrategy
        nsView.scheduleConfiguration()
    }

    final class ConfiguratorView: NSView {
        var configure: ((NSScrollView) -> Void)?
        var searchStrategy: SearchStrategy = .nearestOrFallback

        private var isConfigurationScheduled = false

        override var intrinsicContentSize: NSSize {
            NSSize(width: 0, height: 0)
        }

        override var fittingSize: NSSize {
            NSSize(width: 0, height: 0)
        }

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
            guard let scrollView = findScrollView() else {
                scheduleConfiguration()
                return
            }

            configure?(scrollView)
        }

        private func findScrollView() -> NSScrollView? {
            if let enclosingScrollView {
                return enclosingScrollView
            }

            var current: NSView? = superview

            while let view = current {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }

                if searchStrategy == .nearestOrFallback,
                   let scrollView = view.firstDescendant(of: NSScrollView.self) {
                    return scrollView
                }

                current = view.superview
            }

            guard searchStrategy == .nearestOrFallback else {
                return nil
            }

            return window?.contentView?.firstDescendant(of: NSScrollView.self)
        }
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }

        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}
