import Foundation

/// The month grid: Monday-first weeks, nil-padded at both ends — pure so
/// the week math is testable without a view.
enum MiniCalendarModel {
    static func weeks(
        containing day: DateKey, calendar: Calendar = .current
    ) -> [[DateKey?]] {
        var calendar = calendar
        calendar.firstWeekday = 2  // Monday, like every date in this app.
        let anchor = day.date(calendar: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: anchor)
        else { return [] }
        let first = DateKey(interval.start, calendar: calendar)
        let dayCount = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 30
        // Weekday of the 1st, expressed Monday=0 … Sunday=6.
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [DateKey?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(first.advanced(by: offset, calendar: calendar))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}
