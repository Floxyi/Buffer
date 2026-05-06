import AppKit
import SwiftUI

struct HistoryImageDetailContent: View {
    let item: ClipboardItem
    let previewImage: NSImage?
    let isExtractingText: Bool
    let onCopyOCRText: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: HistoryWindowStyle.imagePreviewHeight
                        )
                } else {
                    ProgressView()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity)
            .frame(height: HistoryWindowStyle.imagePreviewHeight)

            if isExtractingText {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 12)
            } else if let ocrText = item.ocrText {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 0.5)

                    HStack(alignment: .top) {
                        Text(ocrText)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        Button(action: {
                            onCopyOCRText(ocrText)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Copy extracted text")
                    }
                    .padding(.top, 12)
                }
            }
        }
    }
}
