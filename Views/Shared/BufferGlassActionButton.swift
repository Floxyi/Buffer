import SwiftUI

struct BufferGlassActionButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .bufferGlassSurface(cornerRadius: 14, interactive: true)
        .help(help)
    }
}
