import AppKit
import Foundation

struct ClipboardColorVariant: Equatable, Sendable {
    let format: ClipboardColorFormat
    let label: String
    let value: String
}

enum ClipboardColorFormat: String, CaseIterable, Codable, Sendable {
    case hex
    case rgb
    case hsl

    var label: String {
        rawValue.uppercased()
    }
}

struct ClipboardColorValue: Codable, Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var nsColor: NSColor {
        NSColor(
            calibratedRed: red.clamped(to: 0...1),
            green: green.clamped(to: 0...1),
            blue: blue.clamped(to: 0...1),
            alpha: alpha.clamped(to: 0...1)
        )
    }

    var isOpaque: Bool {
        abs(alpha.clamped(to: 0...1) - 1.0) < 0.000_1
    }

    static func parse(_ string: String) -> ClipboardColorValue? {
        ClipboardColorParser.parse(string)
    }

    static func fallback(from string: String) -> ClipboardColorValue {
        parse(string) ?? ClipboardColorValue(red: 0, green: 0, blue: 0, alpha: 1)
    }

    func formatted(as format: ClipboardColorFormat) -> String {
        ClipboardColorFormatter.formatted(self, as: format)
    }
}
