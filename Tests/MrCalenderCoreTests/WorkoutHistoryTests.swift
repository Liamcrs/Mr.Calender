import XCTest
@testable import MrCalenderCore

final class WorkoutHistoryTests: XCTestCase {
    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value + "Z")!
    }

    func testRecordsUseInclusiveStartAndExclusiveEnd() {
        let start = date("2026-09-01T00:00:00")
        let end = date("2026-10-01T00:00:00")
        let manual = [
            ManualWorkout(kind: .walking, minutes: 10, date: start),
            ManualWorkout(kind: .running, minutes: 20, date: end)
        ]

        let result = WorkoutHistory.records(manual: manual, health: [], from: start, to: end)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .walking)
        XCTAssertEqual(result[0].source, .manual)
    }

    func testRecordsAreNewestFirstAndRemoveDuplicateIDs() {
        let start = date("2026-09-01T00:00:00")
        let end = date("2026-10-01T00:00:00")
        let older = WorkoutRecord(id: "health-older", kind: .walking, minutes: 15,
                                  distanceKM: 1.2, source: .appleHealth,
                                  date: date("2026-09-10T08:00:00"))
        let newer = WorkoutRecord(id: "health-newer", kind: .running, minutes: 30,
                                  distanceKM: 5, source: .appleHealth,
                                  date: date("2026-09-20T18:00:00"))

        let result = WorkoutHistory.records(manual: [], health: [older, newer, newer], from: start, to: end)

        XCTAssertEqual(result.map(\.id), ["health-newer", "health-older"])
    }

    func testManualRecordIDIsStableAndNamespaced() {
        let id = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let record = ManualWorkout(id: id, kind: .swimming, minutes: 45,
                                   distanceKM: 1.5, date: date("2026-09-12T12:00:00"))

        let result = WorkoutHistory.records(
            manual: [record], health: [],
            from: date("2026-09-01T00:00:00"), to: date("2026-10-01T00:00:00")
        )

        XCTAssertEqual(result.single?.id, "manual-\(id.uuidString)")
        XCTAssertEqual(result.single?.title, "游泳")
    }

    func testCommonAppleWorkoutKindsHaveSpecificChineseTitles() {
        XCTAssertEqual(WorkoutKind.cycling.title, "骑行")
        XCTAssertEqual(WorkoutKind.strengthTraining.title, "力量训练")
        XCTAssertEqual(WorkoutKind.badminton.title, "羽毛球")
        XCTAssertEqual(WorkoutKind.other.title, "其他运动")
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
