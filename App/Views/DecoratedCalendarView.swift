import SwiftUI
import UIKit

struct DecoratedCalendarView: UIViewRepresentable {
    @Binding var selectedDate: Date
    let snapshot: AppSnapshot
    var calendar: Calendar = .current

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = calendar
        view.locale = .current
        view.timeZone = calendar.timeZone
        view.delegate = context.coordinator
        view.wantsDateDecorations = true
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.setSelected(calendar.dateComponents([.year, .month, .day], from: selectedDate), animated: false)
        view.selectionBehavior = selection
        context.coordinator.decoratedDates = context.coordinator.eventDates(snapshot)
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let oldDates = context.coordinator.decoratedDates
        context.coordinator.parent = self
        let newDates = context.coordinator.eventDates(snapshot)
        context.coordinator.decoratedDates = newDates
        let selected = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           selection.selectedDate != selected {
            selection.setSelected(selected, animated: false)
        }
        let changed = Array(oldDates.union(newDates))
        if !changed.isEmpty { view.reloadDecorations(forDateComponents: changed, animated: true) }
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DecoratedCalendarView
        var decoratedDates = Set<DateComponents>()

        init(parent: DecoratedCalendarView) { self.parent = parent }

        func eventDates(_ snapshot: AppSnapshot) -> Set<DateComponents> {
            Set(snapshot.events.map {
                parent.calendar.dateComponents([.year, .month, .day], from: $0.startsAt)
            })
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            guard let dateComponents, let date = parent.calendar.date(from: dateComponents) else { return }
            parent.selectedDate = date
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
            return .customView {
                DayIndicatorDots(indicators: indicators)
            }
        }
    }
}

private final class DayIndicatorDots: UIStackView {
    init(indicators: [DayIndicator]) {
        super.init(frame: .zero)
        axis = .horizontal
        spacing = 2
        alignment = .center
        distribution = .equalCentering
        isAccessibilityElement = true
        accessibilityLabel = indicators.map(\.accessibilityTitle).joined(separator: "、")
        for indicator in indicators {
            let dot = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = indicator.color
            dot.layer.cornerRadius = 2.5
            dot.layer.borderColor = UIColor.systemBackground.cgColor
            dot.layer.borderWidth = 0.75
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 5),
                dot.heightAnchor.constraint(equalToConstant: 5)
            ])
            addArrangedSubview(dot)
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
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
