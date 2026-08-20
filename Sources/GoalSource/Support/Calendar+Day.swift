import Foundation

public extension Calendar {
    func goalDayInterval(containing date: Date) -> DateInterval {
        if let interval = dateInterval(of: .day, for: date) {
            return interval
        }
        let start = startOfDay(for: date)
        return DateInterval(start: start, duration: 24 * 60 * 60)
    }

    func goalDayKey(for date: Date) -> String {
        let parts = dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}
