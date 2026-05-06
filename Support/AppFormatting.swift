import Foundation

enum AppFormatting {
    private static let keyCodeNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 10: "§", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        49: "Space", 50: "`"
    ]

    static func historySectionTitle(for date: Date, calendar: Calendar = .current, referenceDate: Date = Date()) -> String {
        if calendar.isDateInToday(date) {
            return "TODAY"
        }

        if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        }

        if calendar.isDate(date, equalTo: referenceDate, toGranularity: .weekOfYear) {
            return "THIS WEEK"
        }

        if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: referenceDate),
           calendar.isDate(date, equalTo: lastWeek, toGranularity: .weekOfYear) {
            return "LAST WEEK"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date).uppercased()
    }

    static func formattedByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func formattedSize(bytes: Int) -> String {
        formattedByteCount(bytes)
    }

    static func keyDisplayName(for keyCode: UInt16) -> String {
        keyCodeNames[keyCode] ?? "?"
    }

    static func shortcutDisplay(modifiers: HotkeyModifiers, keyCode: UInt16) -> String {
        "\(modifiers.displayString)\(keyDisplayName(for: keyCode))"
    }
}
