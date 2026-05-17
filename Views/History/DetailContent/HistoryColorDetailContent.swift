import SwiftUI

struct HistoryColorDetailContent: View {
    let item: ClipboardItem
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let onCopyColorVariant: (String) -> Void

    private var fontSize: CGFloat {
        CGFloat(textDetailFontSize.rawValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let colorPayload = item.colorPayload {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: colorPayload.value.nsColor))
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Copy as")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.75))

                    ForEach(colorPayload.formattedVariants, id: \.format) { variant in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(variant.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 34, alignment: .leading)

                            Text(variant.value)
                                .font(.system(size: fontSize))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: {
                                onCopyColorVariant(variant.value)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help("Copy \(variant.label)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}
