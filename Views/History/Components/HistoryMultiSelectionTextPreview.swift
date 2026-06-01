import SwiftUI

struct HistoryMultiSelectionTextPreview: View {
    private static let collapsedLineLimit = 10
    private static let overflowCharacterThreshold = 800

    let text: String
    let isExpanded: Bool
    let textDetailFontStyle: TextDetailFontStyle
    let textDetailFontSize: TextDetailFontSize
    let onToggleExpanded: () -> Void

    private var fontSize: CGFloat {
        CGFloat(textDetailFontSize.rawValue)
    }

    private var usesMonospacedFont: Bool {
        textDetailFontStyle == .monospaced
    }

    private var font: Font {
        usesMonospacedFont
            ? .system(size: fontSize, design: .monospaced)
            : .system(size: fontSize)
    }

    private var showsExpansionToggle: Bool {
        let explicitLineCount = text.components(separatedBy: .newlines).count
        return explicitLineCount > Self.collapsedLineLimit || text.count > Self.overflowCharacterThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(font)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .multilineTextAlignment(.leading)

            if showsExpansionToggle {
                Button(isExpanded ? "Show less" : "Show more", action: onToggleExpanded)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.82))
            }
        }
    }
}
