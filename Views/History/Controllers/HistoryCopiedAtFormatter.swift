import Foundation

struct HistoryCopiedAtFormatter {
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, d. MMMM yyyy, 'at' HH:mm"
        return formatter
    }()

    func string(for timestamp: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let effectiveCalendar = calendar

        if effectiveCalendar.isDate(timestamp, inSameDayAs: now) {
            let elapsedMinutes = max(1, Int(now.timeIntervalSince(timestamp) / 60))

            if elapsedMinutes < 60 {
                return elapsedMinutes == 1 ? "1 minute ago" : "\(elapsedMinutes) minutes ago"
            }

            let elapsedHours = max(1, elapsedMinutes / 60)
            return elapsedHours == 1 ? "1 hour ago" : "\(elapsedHours) hours ago"
        }

        if let yesterday = effectiveCalendar.date(byAdding: .day, value: -1, to: now),
           effectiveCalendar.isDate(timestamp, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        return Self.absoluteFormatter.string(from: timestamp)
    }
}
