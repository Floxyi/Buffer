import CoreGraphics
import Foundation
import SwiftUI

enum ClipboardMeasuredScrollGeometry {
    enum ExactTarget {
        case alreadyVisible
        case scrollTo(CGFloat)
    }

    static func attemptCount(for alignment: ClipboardMeasuredScrollRequest.Alignment) -> Int {
        alignment == .centered ? 16 : 5
    }

    static func anchor(for alignment: ClipboardMeasuredScrollRequest.Alignment) -> UnitPoint {
        alignment == .centered ? .center : UnitPoint(x: 0.5, y: 0.5)
    }

    static func shouldUseProxyScroll(
        alignment: ClipboardMeasuredScrollRequest.Alignment,
        measuredTargetFrame: CGRect?,
        attempt: Int
    ) -> Bool {
        switch alignment {
        case .centered:
            return measuredTargetFrame == nil || attempt < 4
        case .visible:
            return measuredTargetFrame == nil && attempt >= 2
        }
    }

    static func estimatedTargetOffset(
        estimatedMidY: CGFloat,
        viewportHeight: CGFloat,
        alignment: ClipboardMeasuredScrollRequest.Alignment
    ) -> CGFloat {
        let targetY =
            alignment == .centered
            ? viewportHeight / 2
            : viewportHeight * 0.35
        return estimatedMidY - targetY
    }

    static func exactTarget(
        measuredTargetFrame: CGRect,
        viewportHeight: CGFloat,
        currentOffset: CGFloat,
        contentHeight: CGFloat,
        alignment: ClipboardMeasuredScrollRequest.Alignment
    ) -> ExactTarget {
        let maxOffset = max(0, contentHeight - viewportHeight)
        let rawTargetOffset: CGFloat

        switch alignment {
        case .centered:
            rawTargetOffset = measuredTargetFrame.midY - viewportHeight / 2

        case .visible:
            let edgePadding = CGFloat(10)
            let visibleMinY = currentOffset + edgePadding
            let visibleMaxY = currentOffset + viewportHeight - edgePadding

            if measuredTargetFrame.minY >= visibleMinY,
                measuredTargetFrame.maxY <= visibleMaxY
            {
                return .alreadyVisible
            }

            if measuredTargetFrame.minY < visibleMinY {
                rawTargetOffset = measuredTargetFrame.minY - edgePadding
            } else {
                rawTargetOffset = measuredTargetFrame.maxY - viewportHeight + edgePadding
            }
        }

        return .scrollTo(rawTargetOffset.clamped(to: 0...maxOffset))
    }
}
