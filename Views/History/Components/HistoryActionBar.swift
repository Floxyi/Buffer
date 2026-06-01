import SwiftUI

struct HistoryActionBar: View {
    let showsPinnedShortcutAsUnpin: Bool
    let showsSaveShortcut: Bool
    let showsJumpToHistory: Bool
    let onJumpToHistory: () -> Void
    let onPaste: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                BufferShortcutHint(shortcut: "⇧ ↑↓", label: "Select")
                BufferShortcutHint(shortcut: "⌘ P", label: showsPinnedShortcutAsUnpin ? "Unpin" : "Pin")
                
                if showsSaveShortcut {
                    BufferShortcutHint(shortcut: "⌘ S", label: "Save")
                }
                
                BufferShortcutHint(shortcut: "⌥", label: "Copy", shortcutSymbolName: "return")
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()

                if showsJumpToHistory {
                    Button(action: onJumpToHistory) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 10, weight: .medium))

                            Text("history")
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
