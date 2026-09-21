import XCTest
@testable import MrCalenderCore

final class TimetableTests: XCTestCase {
    private let legacyID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testSchemaTwoCoursesMigrateIntoOneEnabledTimetable() throws {
        let json = """
        {
          "schemaVersion": 2,
          "events": [{
            "id": "legacy-course",
            "title": "高等数学",
            "startsAt": 1788748800,
            "endsAt": 1788754200,
            "isAllDay": false,
            "location": "A101",
            "notes": "课程代码 MATH101",
            "source": "course",
            "importedUID": "math@example.edu",
            "reminderMinutes": 15
          }]
        }
        """.data(using: .utf8)!

        let snapshot = try SnapshotStore.decode(json)

        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertEqual(snapshot.timetables.count, 1)
        XCTAssertEqual(snapshot.timetables[0].id, legacyID)
        XCTAssertEqual(snapshot.timetables[0].name, "已导入课表")
        XCTAssertTrue(snapshot.timetables[0].isEnabled)
        XCTAssertEqual(snapshot.events[0].timetableID, legacyID)
    }

    func testSchemaTwoWithoutCoursesDoesNotCreateTimetable() throws {
        let json = """
        {"schemaVersion":2,"events":[],"restaurants":[],"dishes":[],"meals":[]}
        """.data(using: .utf8)!

        let snapshot = try SnapshotStore.decode(json)

        XCTAssertEqual(snapshot.schemaVersion, 3)
        XCTAssertTrue(snapshot.timetables.isEmpty)
    }

    func testSchemaThreeRoundTripDoesNotDuplicateTimetables() throws {
        var snapshot = AppSnapshot()
        let timetable = Timetable(name: "大二上", importedAt: Date(timeIntervalSince1970: 1_700_000_000))
        snapshot.timetables = [timetable]
        snapshot.events = [CalendarEvent(
            title: "计算机网络",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            endsAt: Date(timeIntervalSince1970: 1_800_003_600),
            source: .course,
            importedUID: "network@example.edu",
            timetableID: timetable.id
        )]

        let once = try SnapshotStore.decode(SnapshotStore.encode(snapshot))
        let twice = try SnapshotStore.decode(SnapshotStore.encode(once))

        XCTAssertEqual(once, twice)
        XCTAssertEqual(twice.timetables, [timetable])
    }
}
