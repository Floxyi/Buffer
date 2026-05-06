import SwiftUI

struct ClipboardScrollToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .symbolRenderingMode(.monochrome)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .frame(width: 28, height: 28)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .bufferGlassSurface(cornerRadius: 14, interactive: true)
        .padding(.bottom, 12)
    }
}
