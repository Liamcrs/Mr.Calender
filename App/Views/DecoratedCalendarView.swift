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
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        let oldState = context.coordinator.decorationState
        context.coordinator.parent = self
        let newState = DecorationState(snapshot: snapshot, calendar: calendar)
        let selected = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           selection.selectedDate != selected {
            selection.setSelected(selected, animated: false)
        }
        if oldState != newState {
            context.coordinator.decorationState = newState
            let changed = Array(oldState.dates.union(newState.dates))
            if !changed.isEmpty { view.reloadDecorations(forDateComponents: changed, animated: true) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: DecoratedCalendarView
        fileprivate var decorationState: DecorationState

        init(parent: DecoratedCalendarView) {
            self.parent = parent
            decorationState = DecorationState(snapshot: parent.snapshot, calendar: parent.calendar)
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

private struct DecorationInput: Hashable {
    let date: DateComponents
    let indicator: DayIndicator
}

private struct DecorationState: Equatable {
    let inputs: [DecorationInput]

    init(snapshot: AppSnapshot, calendar: Calendar) {
        inputs = Set(snapshot.activeEvents.map { event in
            DecorationInput(
                date: calendar.dateComponents([.year, .month, .day], from: event.startsAt),
                indicator: event.source == .course ? .course : .customEvent
            )
        }).sorted { left, right in
            let leftKey = [left.date.year ?? 0, left.date.month ?? 0, left.date.day ?? 0, left.indicator.rawValue]
            let rightKey = [right.date.year ?? 0, right.date.month ?? 0, right.date.day ?? 0, right.indicator.rawValue]
            return leftKey.lexicographicallyPrecedes(rightKey)
        }
    }

    var dates: Set<DateComponents> { Set(inputs.map(\.date)) }
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
            dot.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
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
