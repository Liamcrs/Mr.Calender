import Foundation

public enum DayIndicator: Int, CaseIterable, Hashable, Sendable {
    case holiday
    case course
    case customEvent
}

public enum CalendarIndicators {
    public static func indicators(
        on date: Date,
        snapshot: AppSnapshot,
        calendar: Calendar = .current
    ) -> [DayIndicator] {
        var values = Set<DayIndicator>()
        if HolidayProvider.labels(on: date, calendar: calendar).contains(where: { $0.kind != .workday }) {
            values.insert(.holiday)
        }
        for event in snapshot.activeEvents where calendar.isDate(event.startsAt, inSameDayAs: date) {
            values.insert(event.source == .course ? .course : .customEvent)
        }
        return DayIndicator.allCases.filter(values.contains)
    }
}
