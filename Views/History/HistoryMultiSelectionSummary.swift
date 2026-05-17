import SwiftUI

struct HistoryMultiSelectionSummary: View {
    let selectionCount: Int
    let selectedItemsTotalSizeText: String
    let textCount: Int
    let imageCount: Int
    let colorCount: Int
    let linkCount: Int
    let firstTextPreview: String?
    let onDownloadAllImages: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                HistoryStatBlock(title: "Items", value: "\(selectionCount)")
                HistoryStatBlock(title: "Total Size", value: selectedItemsTotalSizeText)
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if textCount > 0 {
                    HistoryTypeCountRow(
                        systemName: "doc.text",
                        text: "\(textCount) text \(textCount == 1 ? "item" : "items")"
                    )
                }

                if colorCount > 0 {
                    HistoryTypeCountRow(
                        systemName: "paintpalette",
                        text: "\(colorCount) color \(colorCount == 1 ? "item" : "items")"
                    )
                }

                if linkCount > 0 {
                    HistoryTypeCountRow(
                        systemName: "link",
                        text: "\(linkCount) link \(linkCount == 1 ? "item" : "items")"
                    )
                }

                if imageCount > 0 {
                    HistoryTypeCountRow(
                        systemName: "photo",
                        text: "\(imageCount) image \(imageCount == 1 ? "item" : "items")"
                    )
                }
            }

            Divider()

            if textCount == 0 && imageCount > 0 {
                Button(action: onDownloadAllImages) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                        Text("Download All (\(imageCount))")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider()
            }

            if let firstTextPreview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("First item preview")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))

                    Text(firstTextPreview)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(4)
                        .truncationMode(.tail)
                }
            }
        }
    }
}
