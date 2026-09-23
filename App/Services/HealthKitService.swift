import Foundation
import HealthKit

enum HealthAccessResult {
    case authorizationRequested
    case alreadyHandled
    case unknown
}

final class HealthKitService {
    private let store = HKHealthStore()
    func requestAccess() async throws -> HealthAccessResult {
        guard HKHealthStore.isHealthDataAvailable() else { throw NSError(domain: "MrCalender", code: 10, userInfo: [NSLocalizedDescriptionKey: "此设备暂不支持健康数据"]) }
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.activitySummaryType()
        ]
        let status = try await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        switch status {
        case .shouldRequest:
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return .authorizationRequested
        case .unnecessary:
            return .alreadyHandled
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
    func workouts(from start: Date, to end: Date) async throws -> [HKWorkout] {
        guard start < end else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }; store.execute(query)
        }
    }

    func activitySummaries(from start: Date, to end: Date, calendar: Calendar) async throws -> [DailyActivitySummary] {
        guard start <= end else { return [] }
        let range = ActivitySummaryQueryRange(from: start, to: end, calendar: calendar)
        let predicate = HKQuery.predicate(
            forActivitySummariesBetweenStart: range.start,
            end: range.end
        )
        let descriptor = HKActivitySummaryQueryDescriptor(predicate: predicate)
        return try await descriptor.result(for: store).compactMap { summary in
            map(summary, calendar: range.calendar)
        }
    }

    private func map(_ summary: HKActivitySummary, calendar: Calendar) -> DailyActivitySummary? {
        let components = summary.dateComponents(for: calendar)
        guard let date = calendar.date(from: components) else { return nil }
        return DailyActivitySummary(
            date: date,
            activeEnergy: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
            activeEnergyGoal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
            exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
            exerciseGoal: (summary.exerciseTimeGoal ?? summary.appleExerciseTimeGoal).doubleValue(for: .minute()),
            standHours: summary.appleStandHours.doubleValue(for: .count()),
            standGoal: (summary.standHoursGoal ?? summary.appleStandHoursGoal).doubleValue(for: .count())
        )
    }
}
