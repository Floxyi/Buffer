import Foundation

enum ClipboardColorFormatter {
    static func formatted(_ color: ClipboardColorValue, as format: ClipboardColorFormat) -> String {
        switch format {
        case .hex:
            return formattedHex(color)
        case .rgb:
            return formattedRGB(color)
        case .hsl:
            return formattedHSL(color)
        }
    }

    private static func formattedHex(_ color: ClipboardColorValue) -> String {
        let redComponent = Int((color.red.clamped(to: 0...1) * 255.0).rounded())
        let greenComponent = Int((color.green.clamped(to: 0...1) * 255.0).rounded())
        let blueComponent = Int((color.blue.clamped(to: 0...1) * 255.0).rounded())
        let alphaComponent = Int((color.alpha.clamped(to: 0...1) * 255.0).rounded())

        if color.isOpaque {
            return String(format: "#%02X%02X%02X", redComponent, greenComponent, blueComponent)
        }

        return String(format: "#%02X%02X%02X%02X", redComponent, greenComponent, blueComponent, alphaComponent)
    }

    private static func formattedRGB(_ color: ClipboardColorValue) -> String {
        let redComponent = Int((color.red.clamped(to: 0...1) * 255.0).rounded())
        let greenComponent = Int((color.green.clamped(to: 0...1) * 255.0).rounded())
        let blueComponent = Int((color.blue.clamped(to: 0...1) * 255.0).rounded())

        if color.isOpaque {
            return "rgb(\(redComponent), \(greenComponent), \(blueComponent))"
        }

        return "rgba(\(redComponent), \(greenComponent), \(blueComponent), \(formattedAlphaComponent(color.alpha)))"
    }

    private static func formattedHSL(_ color: ClipboardColorValue) -> String {
        let hsl = ClipboardColorHSLConverter.toHSL(color)
        let hue = Int(hsl.hue.rounded())
        let saturation = Int((hsl.saturation * 100.0).rounded())
        let lightness = Int((hsl.lightness * 100.0).rounded())

        if color.isOpaque {
            return "hsl(\(hue), \(saturation)%, \(lightness)%)"
        }

        return "hsla(\(hue), \(saturation)%, \(lightness)%, \(formattedAlphaComponent(color.alpha)))"
    }

    private static func formattedAlphaComponent(_ alpha: Double) -> String {
        let rounded = (alpha.clamped(to: 0...1) * 100.0).rounded() / 100.0
        if rounded == floor(rounded) {
            return String(format: "%.0f", rounded)
        }

        return String(format: "%.2f", rounded)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

