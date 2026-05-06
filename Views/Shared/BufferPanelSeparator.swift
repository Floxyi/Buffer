import SwiftUI

struct BufferPanelSeparator: View {
    var isVertical: Bool = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: isVertical ? 1 : nil, height: isVertical ? nil : 1)
    }
}
