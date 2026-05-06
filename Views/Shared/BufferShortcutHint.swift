import SwiftUI

struct BufferShortcutHint: View {
    let shortcut: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(shortcut)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )

            Text(label)
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary.opacity(0.6))
    }
}
