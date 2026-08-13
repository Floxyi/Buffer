import SwiftUI

struct BufferWindowBackdrop: View {
    @Environment(\.bufferAppearance) private var appearance

    var body: some View {
        switch appearance.surfaceStyle {
        case .glass:
            gradientBackdrop(baseOpacity: 0.24, highlightOpacity: 0.08)
        case .transparent:
            gradientBackdrop(baseOpacity: 0.08, highlightOpacity: 0.04)
        case .opaque:
            Color(nsColor: .windowBackgroundColor)
        }
    }

    private func gradientBackdrop(
        baseOpacity: Double,
        highlightOpacity: Double
    ) -> some View {
        ZStack {
            Color.black.opacity(baseOpacity)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.18),
                    Color.clear,
                    Color.black.opacity(0.10),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.clear,
                    Color.white.opacity(0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .background(Color.clear)
    }
}
