import CoreGraphics
import Foundation

@MainActor
final class ClipboardKeyboardNavigationCoordinator {
    enum Result: Equatable {
        case stale
        case unavailable
        case alreadyVisible
        case scrolled

        var didApplyViewportOperation: Bool {
            self == .alreadyVisible || self == .scrolled
        }
    }

    private var latestGeneration: UInt = 0
    private var invalidatedGeneration: UInt = 0

    func invalidateCurrentRequest() {
        invalidatedGeneration = max(invalidatedGeneration, latestGeneration)
    }

    func scrollSelectedItemIntoView(
        request: HistoryKeyboardScrollRequest,
        targetFrameExists: Bool,
        scrollController: ScrollController,
        resolveMetrics: (UUID) -> (currentOffset: CGFloat, targetOffset: CGFloat)?
    ) -> Result {
        guard request.generation > invalidatedGeneration,
            request.generation >= latestGeneration
        else {
            return .stale
        }

        latestGeneration = request.generation
        guard targetFrameExists else { return .unavailable }
        guard let metrics = resolveMetrics(request.itemID) else {
            return .alreadyVisible
        }
        guard abs(metrics.targetOffset - metrics.currentOffset) > 0.5 else {
            return .alreadyVisible
        }

        // scrollTo updates the AppKit viewport and synchronizes the metrics itself.
        scrollController.scrollTo(offset: metrics.targetOffset)
        return .scrolled
    }
}
