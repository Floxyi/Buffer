import SwiftUI

struct HistoryTextDetailContent: View {
    let item: ClipboardItem
    let chunkedText: ChunkedTextState
    let onLoadNextChunk: (ClipboardItem) -> Void

    var body: some View {
        if item.isTruncated {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.textContent ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
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
            LazyVStack(spacing: 8, pinnedViews: []) {
                Text(chunkedText.visibleText)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
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
            Text(item.textContent ?? "")
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
