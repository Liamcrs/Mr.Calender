import Foundation

/// Civil-date bounds for HealthKit's inclusive activity-summary predicate.
public struct ActivitySummaryQueryRange {
    public let calendar: Calendar
    public let start: DateComponents
    public let end: DateComponents

    public init(from start: Date, to end: Date, calendar: Calendar) {
        var queryCalendar = Calendar(identifier: .gregorian)
        queryCalendar.timeZone = calendar.timeZone
        self.calendar = queryCalendar
        // HealthKit requires the calendar on both bounds; keep the caller's zone
        // on the components as well as the Gregorian calendar that interprets them.
        let fields: Set<Calendar.Component> = [.calendar, .timeZone, .era, .year, .month, .day]
        self.start = queryCalendar.dateComponents(fields, from: start)
        self.end = queryCalendar.dateComponents(fields, from: end)
    }
}
