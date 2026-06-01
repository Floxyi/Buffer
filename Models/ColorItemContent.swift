import Foundation

struct ColorItemContent: Codable, Equatable, Sendable {
    let value: ClipboardColorValue
    let originalText: String

    var formattedVariants: [ClipboardColorVariant] {
        ClipboardColorFormat.allCases.map { format in
            ClipboardColorVariant(
                format: format,
                label: format.label,
                value: value.formatted(as: format)
            )
        }
    }
}
