import SwiftUI

struct ActivitySummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let days: [ActivityDay]
    let today: Date
    let measured: DailyActivityMetrics?
    var calendar: Calendar = .current

    private var todayDay: ActivityDay? { days.first }
    private var previousDays: ArraySlice<ActivityDay> { days.dropFirst().prefix(3) }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            todayPanel
            previousDaysPanel
        }
        .accessibilityElement(children: .contain)
    }

    private var todayPanel: some View {
        VStack(spacing: 8) {
            ActivityRings(summary: todayDay?.summary, date: todayDay?.date ?? today, size: 128)
            Text(label(for: todayDay?.date ?? today))
                .font(.caption)
                .foregroundStyle(.secondary)
            ActivityValues(values: ActivityPresentation.values(
                summary: todayDay?.summary, measured: measured
            ))
        }
        .frame(maxWidth: .infinity)
    }

    private var previousDaysPanel: some View {
        VStack(spacing: 8) {
            ForEach(Array(previousDays), id: \.date) { day in
                HStack(spacing: 8) {
                    ActivityRings(summary: day.summary, date: day.date, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label(for: day.date)).font(.caption.bold())
                        if day.records.count == 1, let record = day.records.first {
                            Text("\(record.title) \(record.minutes) 分钟")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(record.source.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(day.workoutText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func label(for date: Date) -> String {
        ActivityPresentation.dateLabel(date, relativeTo: today, calendar: calendar, locale: .current)
    }
}

private struct ActivityValues: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let values: DailyActivityMetrics?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 7))
            : AnyLayout(HStackLayout(spacing: 7))
        layout {
            value(values?.activeEnergy, unit: "千卡", color: .pink)
            value(values?.exerciseMinutes, unit: "分钟", color: .green)
            value(values?.standHours, unit: "小时", color: .cyan)
        }
    }

    private func value(_ number: Double?, unit: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(activityNumber(number))
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct ActivityRings: View {
    let summary: DailyActivitySummary?
    let date: Date
    let size: CGFloat

    var body: some View {
        ZStack {
            ring(progress: summary?.moveProgress ?? 0, color: .pink, inset: 0)
            ring(progress: summary?.exerciseProgress ?? 0, color: .green, inset: size * 0.18)
            ring(progress: summary?.standProgress ?? 0, color: .cyan, inset: size * 0.36)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func ring(progress: Double, color: Color, inset: CGFloat) -> some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: max(4, size * 0.075))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: max(4, size * 0.075), lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(inset)
    }

    private var accessibilityText: String {
        let dateText = date.formatted(.dateTime.year().month().day())
        return "\(dateText)，活动（千卡），当前值 \(activityNumber(summary?.activeEnergy))，目标 \(activityNumber(summary?.activeEnergyGoal))；锻炼（分钟），当前值 \(activityNumber(summary?.exerciseMinutes))，目标 \(activityNumber(summary?.exerciseGoal))；站立（小时），当前值 \(activityNumber(summary?.standHours))，目标 \(activityNumber(summary?.standGoal))"
    }
}

private func activityNumber(_ number: Double?) -> String {
    guard let number, number.isFinite else { return "不可用" }
    return number.formatted(.number.precision(.fractionLength(0)))
}
