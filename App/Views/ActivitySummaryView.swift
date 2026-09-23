import SwiftUI

struct ActivitySummaryCard: View {
    let days: [ActivityDay]
    let today: Date
    var calendar: Calendar = .current

    private var todayDay: ActivityDay? { days.first }
    private var previousDays: ArraySlice<ActivityDay> { days.dropFirst().prefix(3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 8) {
                    ActivityRings(summary: todayDay?.summary, date: todayDay?.date ?? today, size: 128)
                    Text(label(for: todayDay?.date ?? today))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ActivityValues(summary: todayDay?.summary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    ForEach(Array(previousDays), id: \.date) { day in
                        HStack(spacing: 8) {
                            ActivityRings(summary: day.summary, date: day.date, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(label(for: day.date)).font(.caption.bold())
                                Text(day.workoutText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func label(for date: Date) -> String {
        ActivityPresentation.dateLabel(date, relativeTo: today, calendar: calendar, locale: .current)
    }
}

private struct ActivityValues: View {
    let summary: DailyActivitySummary?

    var body: some View {
        HStack(spacing: 7) {
            value(summary?.activeEnergy ?? 0, unit: "千卡", color: .pink)
            value(summary?.exerciseMinutes ?? 0, unit: "分钟", color: .green)
            value(summary?.standHours ?? 0, unit: "小时", color: .cyan)
        }
    }

    private func value(_ number: Double, unit: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(number.formatted(.number.precision(.fractionLength(0))))
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
        guard let summary else { return "\(dateText)，没有读取到活动摘要" }
        return "\(dateText)，活动 \(Int(summary.activeEnergy)) 千卡，目标 \(Int(summary.activeEnergyGoal)) 千卡；锻炼 \(Int(summary.exerciseMinutes)) 分钟，目标 \(Int(summary.exerciseGoal)) 分钟；站立 \(Int(summary.standHours)) 小时，目标 \(Int(summary.standGoal)) 小时"
    }
}
