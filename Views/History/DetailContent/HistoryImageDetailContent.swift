import AppKit
import SwiftUI

struct HistoryImageDetailContent: View {
    private static let previewHeightWithoutOCR = CGFloat(333)
    private static let previewHeightWithOCR = CGFloat(220)

    let item: ClipboardItem
    let previewImage: NSImage?
    let isExtractingText: Bool
    let onCopyOCRText: (String) -> Void

    var body: some View {
        Group {
            if isExtractingText {
                VStack(spacing: 12) {
                    previewPanel(height: Self.previewHeightWithoutOCR)

                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 12)
                }
            } else if let ocrText = item.ocrText {
                VStack(spacing: 12) {
                    previewPanel(height: Self.previewHeightWithOCR)

                    extractedTextPanel(ocrText)
                }
            } else {
                previewPanel(height: Self.previewHeightWithoutOCR)
            }
        }
    }

    @ViewBuilder
    private func previewPanel(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    @ViewBuilder
    private func extractedTextPanel(_ ocrText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text("Extracted Text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

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

            Text(ocrText)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
