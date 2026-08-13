import Foundation

struct HistoryCopiedAtFormatter {
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func string(for timestamp: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let effectiveCalendar = calendar

        if effectiveCalendar.isDate(timestamp, inSameDayAs: now) {
            let elapsedMinutes = max(1, Int(now.timeIntervalSince(timestamp) / 60))

            if elapsedMinutes < 60 {
                return elapsedMinutes == 1
                    ? String(localized: "1 minute ago")
                    : String(localized: "\(elapsedMinutes) minutes ago")
            }

            let elapsedHours = max(1, elapsedMinutes / 60)
            return elapsedHours == 1
                ? String(localized: "1 hour ago")
                : String(localized: "\(elapsedHours) hours ago")
        }

        if let yesterday = effectiveCalendar.date(byAdding: .day, value: -1, to: now),
            effectiveCalendar.isDate(timestamp, inSameDayAs: yesterday)
        {
            return String(localized: "Yesterday")
        }

        return Self.absoluteFormatter.string(from: timestamp)
    }
}
