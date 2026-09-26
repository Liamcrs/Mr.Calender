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

public enum DayIndicatorDotLayout {
    public static func width(count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(count * 5 + (count - 1) * 2)
    }
}

/// Event categories by civil day, independent of event titles, IDs, and counts.
public struct CalendarDecorationState: Equatable {
    private let categoriesByDay: [DateComponents: Set<DayIndicator>]

    public init(snapshot: AppSnapshot, calendar: Calendar) {
        var categories: [DateComponents: Set<DayIndicator>] = [:]
        for event in snapshot.activeEvents {
            let day = calendar.dateComponents([.era, .year, .month, .day], from: event.startsAt)
            categories[day, default: []].insert(event.source == .course ? .course : .customEvent)
        }
        categoriesByDay = categories
    }

    public func datesToReload(
        comparedTo previous: Self,
        visibleMonth: DateComponents,
        calendar: Calendar,
        configurationChanged: Bool = false
    ) -> [DateComponents] {
        guard configurationChanged || self != previous,
              visibleMonth.year != nil, visibleMonth.month != nil,
              let visibleDate = calendar.date(from: visibleMonth),
              let month = calendar.dateInterval(of: .month, for: visibleDate),
              let days = calendar.range(of: .day, in: .month, for: visibleDate) else { return [] }

        // Offscreen dates are supplied by the delegate when their month appears.
        return days.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - days.lowerBound, to: month.start) else { return nil }
            let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
            return configurationChanged || categoriesByDay[components] != previous.categoriesByDay[components]
                ? components : nil
        }
    }
}
