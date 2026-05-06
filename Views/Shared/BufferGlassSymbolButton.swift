import SwiftUI

struct BufferGlassSymbolButton: View {
    let help: String
    let systemName: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        BufferGlassActionButton(help: help, action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .resizable()
                .scaledToFit()
                .foregroundStyle(tint)
                .frame(width: 14, height: 14, alignment: .center)
        }
    }
}
