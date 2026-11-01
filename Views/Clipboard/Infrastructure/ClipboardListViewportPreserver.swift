import Foundation
import SwiftUI

struct ClipboardListViewportTransition: Equatable {
    let contentOffset: CGFloat
    let minimumContentHeight: CGFloat

    static let identity = ClipboardListViewportTransition(
        contentOffset: 0,
        minimumContentHeight: 0
    )
}

enum ClipboardListViewportPreservationResolver {
    static func targetOffset(
        from previousSnapshot: ClipboardListContentSnapshot,
        to snapshot: ClipboardListContentSnapshot,
        currentScrollOffset: CGFloat,
        viewportHeight: CGFloat,
        removedItemIDs: Set<UUID>? = nil
    ) -> CGFloat? {
        guard currentScrollOffset > 0.5,
            previousSnapshot.query == snapshot.query
        else { return nil }

        let previousEntries = previousSnapshot.displayCache.layoutIndex.entries
        let nextLayoutIndex = snapshot.displayCache.layoutIndex
        let containsRemoval: Bool
        if let removedItemIDs {
            containsRemoval = removedItemIDs.contains { itemID in
                previousSnapshot.displayCache.layoutIndex.frame(for: itemID) != nil
                    && nextLayoutIndex.frame(for: itemID) == nil
            }
        } else {
            containsRemoval = previousEntries.contains {
                nextLayoutIndex.frame(for: $0.id) == nil
            }
        }
        guard containsRemoval else {
            return nil
        }

        guard
            let anchor = nearestSurvivingAnchor(
                in: previousEntries,
                nextLayoutIndex: nextLayoutIndex,
                scrollOffset: currentScrollOffset
            ),
            let nextFrame = nextLayoutIndex.frame(for: anchor.id)
        else { return nil }
        let offsetFromViewportTop = anchor.frame.minY - currentScrollOffset
        return clampedOffset(
            nextFrame.minY - offsetFromViewportTop,
            contentHeight: nextLayoutIndex.contentHeight,
            viewportHeight: viewportHeight
        )
    }

    private static func nearestSurvivingAnchor(
        in entries: [ClipboardListLayoutIndex.ItemEntry],
        nextLayoutIndex: ClipboardListLayoutIndex,
        scrollOffset: CGFloat
    ) -> ClipboardListLayoutIndex.ItemEntry? {
        guard !entries.isEmpty else { return nil }

        var lowerBound = entries.startIndex
        var upperBound = entries.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if entries[middle].frame.minY <= scrollOffset {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let precedingAnchor = entries.indices.reversed().lazy
            .filter { $0 < lowerBound }
            .map { entries[$0] }
            .first { nextLayoutIndex.frame(for: $0.id) != nil }
        let followingAnchor = entries[lowerBound...].first {
            nextLayoutIndex.frame(for: $0.id) != nil
        }

        return [precedingAnchor, followingAnchor]
            .compactMap { $0 }
            .min { lhs, rhs in
                abs(lhs.frame.minY - scrollOffset) < abs(rhs.frame.minY - scrollOffset)
            }
    }

    private static func clampedOffset(
        _ offset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        offset.clamped(to: 0...max(0, contentHeight - max(0, viewportHeight)))
    }
}

/// Owns viewport continuity for one list-content mutation. Navigation, window
/// restoration, and user scrolling remain separate concerns with separate owners.
@MainActor
final class ClipboardListViewportPreserver: ObservableObject {
    private struct PendingRemoval {
        let snapshot: ClipboardListContentSnapshot
        let removedItemIDs: Set<UUID>
        let scrollOffset: CGFloat
        let viewportHeight: CGFloat
    }

    private var pendingRemoval: PendingRemoval?
    private var releaseTask: Task<Void, Never>?
    private var generation: UInt = 0

    /// Supplies a one-frame visual bridge between the old and new document
    /// geometries. The new rows are translated by the inverse scroll delta
    /// until AppKit installs the matching viewport offset, so no intermediate
    /// jump can reach the display.
    func transition(
        for snapshot: ClipboardListContentSnapshot
    ) -> ClipboardListViewportTransition {
        guard let pendingRemoval,
            let targetOffset = targetOffset(
                for: snapshot,
                pendingRemoval: pendingRemoval
            )
        else { return .identity }

        return ClipboardListViewportTransition(
            contentOffset: pendingRemoval.scrollOffset - targetOffset,
            minimumContentHeight: pendingRemoval.snapshot.displayCache.layoutIndex.contentHeight
        )
    }

    func prepareForRemoval(
        _ itemIDs: Set<UUID>,
        from snapshot: ClipboardListContentSnapshot,
        scrollController: ScrollController
    ) {
        let scrollOffset = scrollController.currentScrollOffsetSnapshot()
        guard !itemIDs.isEmpty,
            scrollOffset > 0.5
        else {
            if pendingRemoval != nil || releaseTask != nil {
                cancel(scrollController: scrollController)
            }
            return
        }

        // A new mutation supersedes both an unfinished preservation and the
        // short release window of the preceding one. Advancing the generation
        // prevents the older delayed task from unlocking this new viewport.
        generation &+= 1
        releaseTask?.cancel()
        releaseTask = nil
        pendingRemoval = PendingRemoval(
            snapshot: snapshot,
            removedItemIDs: itemIDs,
            scrollOffset: scrollOffset,
            viewportHeight: scrollController.currentViewportHeightSnapshot()
        )
        scrollController.beginViewportUpdate(at: scrollOffset)
    }

    func contentDidChange(
        to snapshot: ClipboardListContentSnapshot,
        scrollController: ScrollController
    ) {
        guard let pendingRemoval else {
            return
        }
        guard pendingRemoval.snapshot.query == snapshot.query else {
            cancel(scrollController: scrollController)
            return
        }
        guard
            pendingRemoval.removedItemIDs.allSatisfy({
                snapshot.displayCache.itemIndexByID[$0] == nil
            })
        else {
            return
        }

        guard
            let targetOffset = targetOffset(
                for: snapshot,
                pendingRemoval: pendingRemoval
            )
        else {
            cancel(scrollController: scrollController)
            return
        }

        generation &+= 1
        scrollController.completeViewportUpdate(at: targetOffset)
        self.pendingRemoval = nil
        objectWillChange.send()
        scrollController.syncMetricsImmediately()
        scheduleRelease(scrollController: scrollController, generation: generation)
    }

    func cancel(scrollController: ScrollController) {
        guard pendingRemoval != nil || releaseTask != nil else { return }
        generation &+= 1
        releaseTask?.cancel()
        releaseTask = nil
        pendingRemoval = nil
        objectWillChange.send()
        scrollController.cancelViewportUpdate()
    }

    private func targetOffset(
        for snapshot: ClipboardListContentSnapshot,
        pendingRemoval: PendingRemoval
    ) -> CGFloat? {
        guard pendingRemoval.snapshot.query == snapshot.query,
            pendingRemoval.removedItemIDs.allSatisfy({
                snapshot.displayCache.itemIndexByID[$0] == nil
            })
        else { return nil }

        return ClipboardListViewportPreservationResolver.targetOffset(
            from: pendingRemoval.snapshot,
            to: snapshot,
            currentScrollOffset: pendingRemoval.scrollOffset,
            viewportHeight: pendingRemoval.viewportHeight,
            removedItemIDs: pendingRemoval.removedItemIDs
        )
    }

    private func scheduleRelease(
        scrollController: ScrollController,
        generation scheduledGeneration: UInt
    ) {
        releaseTask?.cancel()
        releaseTask = Task { @MainActor [weak self, weak scrollController] in
            guard let self, let scrollController else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, scheduledGeneration == generation else { return }
            finish(scrollController: scrollController, generation: scheduledGeneration)
        }
    }

    private func finish(scrollController: ScrollController, generation finishedGeneration: UInt) {
        guard finishedGeneration == generation else { return }
        releaseTask = nil
        scrollController.cancelViewportUpdate()
    }
}
