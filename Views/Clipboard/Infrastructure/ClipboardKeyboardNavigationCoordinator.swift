import CoreGraphics
import Foundation

/// Window-scoped output port from synchronous keyboard selection to the AppKit
/// viewport. It deliberately carries no selection ownership: the list may be
/// unavailable and selection remains authoritative in the view model.
@MainActor
final class HistoryKeyboardScrollRouter {
    typealias Handler = @MainActor (HistoryKeyboardScrollRequest) -> Void

    private var registration: (id: UUID, handler: Handler)?

    @discardableResult
    func register(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        registration = (id, handler)
        return id
    }

    func unregister(_ id: UUID) {
        guard registration?.id == id else { return }
        registration = nil
    }

    func submit(_ request: HistoryKeyboardScrollRequest) {
        registration?.handler(request)
    }
}

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
