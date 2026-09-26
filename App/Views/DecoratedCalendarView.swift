import SwiftUI
import UIKit

struct DecoratedCalendarView: UIViewRepresentable {
    @Environment(\.locale) private var locale
    @Binding var selectedDate: Date
    @Binding var visibleMonth: DateComponents
    let snapshot: AppSnapshot
    var calendar: Calendar = .current

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.timeZone = calendar.timeZone
        view.locale = locale
        view.delegate = context.coordinator
        view.wantsDateDecorations = true
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(selectedComponents, animated: false)
        view.selectionBehavior = selection
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let coordinator = context.coordinator
        let oldState = coordinator.decorationState
        let configurationChanged = coordinator.configuration != configuration
        coordinator.parent = self
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        // Update UIKit before it interprets selection components or asks for dots.
        if configurationChanged {
            view.calendar = calendar
            view.timeZone = calendar.timeZone
            view.locale = locale
            coordinator.configuration = configuration
        }
        let newState = CalendarDecorationState(snapshot: snapshot, calendar: calendar)
        coordinator.decorationState = newState
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           configurationChanged || selection.selectedDate.flatMap({ calendar.date(from: $0) })
                .map({ calendar.isDate($0, inSameDayAs: selectedDate) }) != true {
            selection.setSelected(selectedComponents, animated: false)
        }
        let changed = newState.datesToReload(
            comparedTo: oldState,
            visibleMonth: view.visibleDateComponents,
            calendar: calendar,
            configurationChanged: configurationChanged
        )
        if !changed.isEmpty {
            view.reloadDecorations(forDateComponents: changed, animated: !configurationChanged)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICalendarView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let fitted = uiView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: width, height: fitted.height)
    }

    private var selectedComponents: DateComponents {
        calendar.dateComponents([.calendar, .timeZone, .era, .year, .month, .day], from: selectedDate)
    }

    private var configuration: CalendarConfiguration {
        CalendarConfiguration(calendar: calendar, locale: locale)
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DecoratedCalendarView
        fileprivate var decorationState: CalendarDecorationState
        fileprivate var configuration: CalendarConfiguration
        fileprivate var isUpdating = false

        init(parent: DecoratedCalendarView) {
            self.parent = parent
            decorationState = CalendarDecorationState(snapshot: parent.snapshot, calendar: parent.calendar)
            configuration = parent.configuration
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard !isUpdating, let dateComponents,
                  let date = parent.calendar.date(from: dateComponents) else { return }
            parent.selectedDate = date
        }

        func calendarView(
            _ calendarView: UICalendarView,
            didChangeVisibleDateComponentsFrom previousDateComponents: DateComponents
        ) {
            let month = calendarView.visibleDateComponents
            guard parent.visibleMonth != month else { return }
            // A month with more week rows changes UIKit's fitting height. Tell
            // SwiftUI's List to measure this row again without recreating it.
            calendarView.invalidateIntrinsicContentSize()
            parent.visibleMonth = month
        }

        func calendarView(
            _ calendarView: UICalendarView,
            decorationFor dateComponents: DateComponents
        ) -> UICalendarView.Decoration? {
            guard let date = parent.calendar.date(from: dateComponents) else { return nil }
            let indicators = CalendarIndicators.indicators(
                on: date,
                snapshot: parent.snapshot,
                calendar: parent.calendar
            )
            guard !indicators.isEmpty else { return nil }
            return .image(DayIndicatorDots.image(for: indicators), color: nil, size: .large)
        }
    }
}

private struct CalendarConfiguration: Equatable {
    let calendar: Calendar
    let locale: Locale
}

private enum DayIndicatorDots {
    static func image(for indicators: [DayIndicator]) -> UIImage {
        let size = CGSize(width: DayIndicatorDotLayout.width(count: indicators.count), height: 5)
        return UIGraphicsImageRenderer(size: size).image { _ in
            for (index, indicator) in indicators.enumerated() {
                indicator.color.setFill()
                UIBezierPath(ovalIn: CGRect(x: index * 7, y: 0, width: 5, height: 5)).fill()
            }
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

private extension DayIndicator {
    var color: UIColor {
        switch self {
        case .holiday: return .systemBlue
        case .course: return .systemRed
        case .customEvent: return .systemYellow
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .holiday: return "节日或假期"
        case .course: return "课程"
        case .customEvent: return "自定义事务"
        }
    }
}
