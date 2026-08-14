import SwiftUI

struct HistoryActionBar: View {
    let showsBookmarkedShortcutAsRemove: Bool
    let showsPinnedShortcutAsUnpin: Bool
    let showsSaveShortcut: Bool
    let onPaste: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                BufferShortcutHint(shortcut: "⇧ ↑↓", label: "Select")
                BufferShortcutHint(
                    shortcut: "⌘ B",
                    label: showsBookmarkedShortcutAsRemove ? "Unbookmark" : "Bookmark"
                )
                BufferShortcutHint(shortcut: "⌘ P", label: showsPinnedShortcutAsUnpin ? "Unpin" : "Pin")

                if showsSaveShortcut {
                    BufferShortcutHint(shortcut: "⌘ S", label: "Save")
                }

                BufferShortcutHint(shortcut: "⌘ C", label: "Copy")
                BufferShortcutHint(shortcut: "⌘ ⌫", label: "Delete")
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
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
        .background {
            HistoryPanelSurfaceBackground()
        }
    }
}
