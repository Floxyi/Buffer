import SwiftUI

struct HistoryDetailHeader: View {
    let selectionCount: Int
    let isSingleImageSelection: Bool
    let selectedItemIsPinned: Bool
    let canExtractSelectedImageText: Bool
    let isExtractingText: Bool
    let sourceAppName: String?
    let copiedAtText: String?
    let onCopy: () -> Void
    let onSaveImage: () -> Void
    let onExtractText: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if selectionCount <= 1 {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sourceAppName ?? "Unknown App")
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.8))

                    if let copiedAtText {
                        Text(copiedAtText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }

            Spacer()

            if selectionCount > 1 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text("\(selectionCount) items selected")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                }
            }

            Spacer()

            if selectionCount <= 1 {
                HStack(spacing: 10) {
                    BufferGlassSymbolButton(
                        help: "Copy",
                        systemName: "doc.on.doc",
                        action: onCopy
                    )

                    if isSingleImageSelection {
                        BufferGlassSymbolButton(
                            help: "Save image",
                            systemName: "arrow.down.to.line",
                            action: onSaveImage
                        )

                        BufferGlassSymbolButton(
                            help: "Extract Text from Image",
                            systemName: isExtractingText ? "ellipsis.circle" : "text.viewfinder",
                            action: onExtractText
                        )
                        .disabled(!canExtractSelectedImageText)
                    }

                    BufferGlassSymbolButton(
                        help: selectedItemIsPinned ? "Unpin" : "Pin",
                        systemName: selectedItemIsPinned ? "pin.fill" : "pin",
                        tint: selectedItemIsPinned ? .accentColor : .secondary,
                        action: onTogglePin
                    )

                    BufferGlassSymbolButton(
                        help: "Delete",
                        systemName: "trash",
                        action: onDelete
                    )
                }
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(0.18)
        }
    }
}
