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
            HKObjectType.activitySummaryType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.categoryType(forIdentifier: .appleStandHour)!
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

    func todayActivityMetrics(calendar: Calendar) async -> DailyActivityMetrics? {
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let energy = try? await cumulativeValue(
            .activeEnergyBurned, unit: .kilocalorie(), from: start, to: now
        )
        let exercise = try? await cumulativeValue(
            .appleExerciseTime, unit: .minute(), from: start, to: now
        )
        let stand = try? await stoodHours(from: start, to: now, calendar: calendar)
        guard energy != nil || exercise != nil || stand != nil else { return nil }
        return DailyActivityMetrics(
            date: start, activeEnergy: energy, exerciseMinutes: exercise, standHours: stand
        )
    }

    private func cumulativeValue(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date
    ) async throws -> Double? {
        let type = HKObjectType.quantityType(forIdentifier: identifier)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit)) }
            }
            store.execute(query)
        }
    }

    private func stoodHours(from start: Date, to end: Date, calendar: Calendar) async throws -> Double? {
        let type = HKObjectType.categoryType(forIdentifier: .appleStandHour)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let stood = samples.filter { $0.value == HKCategoryValueAppleStandHour.stood.rawValue }
                continuation.resume(returning: Double(ActivityPresentation.standHourCount(
                    sampleDates: stood.map(\.startDate), calendar: calendar
                )))
            }
            store.execute(query)
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
