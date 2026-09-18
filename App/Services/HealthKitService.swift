import Foundation
import HealthKit

final class HealthKitService {
    private let store = HKHealthStore()
    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw NSError(domain: "MrCalender", code: 10, userInfo: [NSLocalizedDescriptionKey: "此设备暂不支持健康数据"]) }
        let workouts = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [], read: [workouts])
    }
    func workouts(on date: Date) async throws -> [HKWorkout] {
        let start = Calendar.current.startOfDay(for: date), end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }; store.execute(query)
        }
    }
}
