import Foundation

enum ClipboardColorHSLConverter {
    static func fromHSL(
        hue: Double,
        saturation: Double,
        lightness: Double,
        alpha: Double
    ) -> ClipboardColorValue {
        let normalizedHue = ((hue.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360) / 360.0

        if saturation == 0 {
            return ClipboardColorValue(red: lightness, green: lightness, blue: lightness, alpha: alpha)
        }

        let q = lightness < 0.5
            ? lightness * (1 + saturation)
            : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q

        func hueToRGB(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t

            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        return ClipboardColorValue(
            red: hueToRGB(p, q, normalizedHue + 1.0 / 3.0),
            green: hueToRGB(p, q, normalizedHue),
            blue: hueToRGB(p, q, normalizedHue - 1.0 / 3.0),
            alpha: alpha
        )
    }

    static func toHSL(_ color: ClipboardColorValue) -> (hue: Double, saturation: Double, lightness: Double) {
        let red = color.red.clamped(to: 0...1)
        let green = color.green.clamped(to: 0...1)
        let blue = color.blue.clamped(to: 0...1)

        let maxComponent = max(red, green, blue)
        let minComponent = min(red, green, blue)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2.0

        guard delta > 0 else {
            return (0, 0, lightness)
        }

        let saturation = lightness > 0.5
            ? delta / (2.0 - maxComponent - minComponent)
            : delta / (maxComponent + minComponent)

        let hueSegment: Double
        if maxComponent == red {
            hueSegment = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxComponent == green {
            hueSegment = ((blue - red) / delta) + 2
        } else {
            hueSegment = ((red - green) / delta) + 4
        }

        let hue = ((hueSegment * 60.0) + 360.0).truncatingRemainder(dividingBy: 360.0)
        return (hue, saturation, lightness)
    }
}

