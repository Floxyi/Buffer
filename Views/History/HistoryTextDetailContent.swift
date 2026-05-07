import SwiftUI

struct HistoryTextDetailContent: View {
    let item: ClipboardItem
    let chunkedText: ChunkedTextState
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let onLoadNextChunk: (ClipboardItem) -> Void

    private var fontSize: CGFloat {
        CGFloat(textDetailFontSize.rawValue)
    }

    private var usesMonospacedFont: Bool {
        textDetailFontStyle == .monospaced
    }

    var body: some View {
        if item.isTruncated {
            VStack(alignment: .leading, spacing: 12) {
                SelectableMonospacedTextView(
                    text: item.textContent ?? "",
                    fontSize: fontSize,
                    usesMonospacedFont: usesMonospacedFont
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Label(
                    "Content was too large to store (\(AppFormatting.formattedSize(bytes: item.originalSizeBytes ?? 0))). Showing first 500 characters.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 8))
                .foregroundColor(.secondary)
                .padding(.top, 4)
            }
        } else if item.isFileBacked {
            VStack(alignment: .leading, spacing: 8) {
                SelectableMonospacedTextView(
                    text: chunkedText.visibleText,
                    fontSize: fontSize,
                    usesMonospacedFont: usesMonospacedFont
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if chunkedText.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 8)
                } else if chunkedText.hasMore {
                    Text("— \(AppFormatting.formattedByteCount(chunkedText.totalBytes)) total · scroll to load more —")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                        .onAppear {
                            onLoadNextChunk(item)
                        }
                }
            }
        } else {
            SelectableMonospacedTextView(
                text: item.textContent ?? "",
                fontSize: fontSize,
                usesMonospacedFont: usesMonospacedFont
            )
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
