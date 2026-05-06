import SwiftUI

struct HistoryActionBar: View {
    let showsSaveShortcut: Bool
    let onPaste: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                BufferShortcutHint(shortcut: "⇧ ↑↓", label: "Select")
                BufferShortcutHint(shortcut: "⌘ P", label: "Pin")

                if showsSaveShortcut {
                    BufferShortcutHint(shortcut: "⌘ S", label: "Save")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()

                Button(action: onPaste) {
                    HStack(spacing: 5) {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .medium))

                        Text("to paste")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.82))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .frame(height: 28)
                .bufferGlassSurface(cornerRadius: 14, interactive: true)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }
}
