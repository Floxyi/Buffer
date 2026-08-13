import Foundation

enum ClipboardColorParser {
    static func parse(_ string: String) -> ClipboardColorValue? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#"), let parsed = parseHex(String(trimmed.dropFirst())) {
            return parsed
        }

        if trimmed.hasPrefix("rgb"), let parsed = parseRGB(trimmed) {
            return parsed
        }

        if trimmed.hasPrefix("hsl"), let parsed = parseHSL(trimmed) {
            return parsed
        }

        return nil
    }

    private static func parseHex(_ hexString: String) -> ClipboardColorValue? {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty else { return nil }
        guard hex.range(of: #"^[0-9a-f]{3}$|^[0-9a-f]{6}$|^[0-9a-f]{8}$"#, options: .regularExpression) != nil else {
            return nil
        }

        if hex.count == 3 {
            let expanded = hex.map { "\($0)\($0)" }.joined()
            return parseHex6(expanded)
        }

        if hex.count == 6 {
            return parseHex6(hex)
        }

        if hex.count == 8 {
            return parseHex8(hex)
        }

        return nil
    }

    private static func parseHex6(_ hex: String) -> ClipboardColorValue? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return ClipboardColorValue(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            alpha: 1
        )
    }

    private static func parseHex8(_ hex: String) -> ClipboardColorValue? {
        guard let value = UInt64(hex, radix: 16) else { return nil }
        return ClipboardColorValue(
            red: Double((value >> 24) & 0xFF) / 255.0,
            green: Double((value >> 16) & 0xFF) / 255.0,
            blue: Double((value >> 8) & 0xFF) / 255.0,
            alpha: Double(value & 0xFF) / 255.0
        )
    }

    private static func parseRGB(_ string: String) -> ClipboardColorValue? {
        let isRGBA = string.hasPrefix("rgba")
        let startOffset = isRGBA ? 5 : 4

        guard string.count > startOffset + 1, string.hasSuffix(")") else { return nil }

        let startIndex = string.index(string.startIndex, offsetBy: startOffset)
        let endIndex = string.index(before: string.endIndex)
        let content = String(string[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3,
            let red = Double(components[0]),
            let green = Double(components[1]),
            let blue = Double(components[2])
        else {
            return nil
        }

        let alpha = isRGBA && components.count >= 4 ? (Double(components[3]) ?? 1) : 1

        return ClipboardColorValue(
            red: red / 255.0,
            green: green / 255.0,
            blue: blue / 255.0,
            alpha: alpha
        )
    }

    private static func parseHSL(_ string: String) -> ClipboardColorValue? {
        let isHSLA = string.hasPrefix("hsla")
        let startOffset = isHSLA ? 5 : 4

        guard string.count > startOffset + 1, string.hasSuffix(")") else { return nil }

        let startIndex = string.index(string.startIndex, offsetBy: startOffset)
        let endIndex = string.index(before: string.endIndex)
        let content = String(string[startIndex..<endIndex]).trimmingCharacters(in: .whitespaces)
        let components = content.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3 else { return nil }

        func parsePercent(_ value: String) -> Double? {
            guard value.hasSuffix("%") else { return nil }
            return Double(value.dropLast()).map { $0 / 100.0 }
        }

        let hueValue =
            components[0].hasSuffix("deg")
            ? String(components[0].dropLast(3))
            : components[0]

        guard let hue = Double(hueValue),
            let saturation = parsePercent(components[1]),
            let lightness = parsePercent(components[2])
        else {
            return nil
        }

        let alpha = isHSLA && components.count >= 4 ? (Double(components[3]) ?? 1) : 1
        return ClipboardColorHSLConverter.fromHSL(
            hue: hue,
            saturation: saturation,
            lightness: lightness,
            alpha: alpha
        )
    }
}
