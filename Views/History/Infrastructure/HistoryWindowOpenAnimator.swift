import Cocoa
import QuartzCore

@MainActor
final class HistoryWindowOpenAnimator {
    private enum Animation {
        static let openDuration: CFTimeInterval = 0.20
        static let fadeDuration: CFTimeInterval = 0.12
        static let openStartScale: CGFloat = 0.965
        static let openStartOpacity: Float = 0

        static func makeScaleTimingFunction() -> CAMediaTimingFunction {
            CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.22, 1.0)
        }

        static func makeFadeTimingFunction() -> CAMediaTimingFunction {
            CAMediaTimingFunction(name: .easeOut)
        }
    }

    private enum AnimationKey {
        static let scale = "buffer.history.open.scale"
        static let opacity = "buffer.history.open.opacity"
    }

    private weak var animatedContentView: NSView?
    private var generation = 0

    func setAnimatedContentView(_ view: NSView) {
        animatedContentView = view
    }

    func beginPresentationCycle(for window: NSWindow) -> (shouldAnimate: Bool, generation: Int) {
        generation += 1
        let currentGeneration = generation
        let shouldAnimate = !window.isVisible

        if shouldAnimate {
            prepareOpenAnimationState(window: window)
        } else {
            resetOpenAnimationState(window: window)
        }

        return (shouldAnimate, currentGeneration)
    }

    func cancelAnimations(for window: NSWindow?) {
        generation += 1
        resetOpenAnimationState(window: window)
    }

    func animateOpenIfNeeded(
        window: NSWindow?,
        shouldAnimate: Bool,
        generation: Int
    ) {
        guard shouldAnimate else { return }
        animateOpen(window: window, generation: generation)
    }

    private func prepareOpenAnimationState(window: NSWindow?) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetOpenAnimationState(window: window)
            return
        }

        guard let layer = prepareAnimatedContentLayer() else {
            return
        }

        performWithoutLayerActions {
            layer.removeAnimation(forKey: AnimationKey.scale)
            layer.removeAnimation(forKey: AnimationKey.opacity)
            layer.transform = CATransform3DMakeScale(
                Animation.openStartScale,
                Animation.openStartScale,
                1
            )
            layer.opacity = Animation.openStartOpacity
        }
    }

    private func animateOpen(window: NSWindow?, generation: Int) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            resetOpenAnimationState(window: window)
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
                Animation.openStartScale,
                Animation.openStartScale,
                1
            )
        )
        scaleAnimation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        scaleAnimation.duration = Animation.openDuration
        scaleAnimation.timingFunction = Animation.makeScaleTimingFunction()
        scaleAnimation.isRemovedOnCompletion = true

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = Animation.openStartOpacity
        opacityAnimation.toValue = 1
        opacityAnimation.duration = Animation.fadeDuration
        opacityAnimation.timingFunction = Animation.makeFadeTimingFunction()
        opacityAnimation.isRemovedOnCompletion = true

        layer.add(scaleAnimation, forKey: AnimationKey.scale)
        layer.add(opacityAnimation, forKey: AnimationKey.opacity)

        Task { @MainActor [weak self, weak window] in
            let delay = UInt64(Animation.openDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            guard let self else { return }
            guard self.generation == generation, window?.isVisible == true else { return }

            self.resetOpenAnimationState(window: window)
        }
    }

    private func resetOpenAnimationState(window: NSWindow?) {
        guard let layer = prepareAnimatedContentLayer() else {
            window?.alphaValue = 1
            return
        }

        performWithoutLayerActions {
            layer.removeAnimation(forKey: AnimationKey.scale)
            layer.removeAnimation(forKey: AnimationKey.opacity)
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
}
