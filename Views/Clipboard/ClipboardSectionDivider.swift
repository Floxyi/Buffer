import SwiftUI

struct ClipboardSectionDivider: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
        .frame(height: ClipboardListStructure.LayoutMetrics.dividerHeight)
    }
}
