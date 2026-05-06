import SwiftUI

struct ClipboardRowSelectionBackground: View {
    let isMultiSelected: Bool
    let joinsSelectionAbove: Bool
    let joinsSelectionBelow: Bool
    let backgroundColor: Color
    let selectionCornerRadius: CGFloat
    let selectionJoinOverlap: CGFloat

    private var shouldExtendAbove: Bool {
        isMultiSelected && joinsSelectionAbove
    }

    private var shouldExtendBelow: Bool {
        isMultiSelected && joinsSelectionBelow
    }

    var body: some View {
        backgroundColor
            .clipShape(selectionShape)
            .padding(.top, shouldExtendAbove ? -selectionJoinOverlap : 0)
            .padding(.bottom, shouldExtendBelow ? -selectionJoinOverlap : 0)
            .allowsHitTesting(false)
    }

    private var selectionShape: some Shape {
        UnevenRoundedRectangle(
            topLeadingRadius: shouldExtendAbove ? 0 : selectionCornerRadius,
            bottomLeadingRadius: shouldExtendBelow ? 0 : selectionCornerRadius,
            bottomTrailingRadius: shouldExtendBelow ? 0 : selectionCornerRadius,
            topTrailingRadius: shouldExtendAbove ? 0 : selectionCornerRadius,
            style: .continuous
        )
    }
}
