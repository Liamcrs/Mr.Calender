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

    func testSchemaOneCourseMigratesIntoLegacyTimetable() throws {
        let json = """
        {
          "schemaVersion": 1,
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
        XCTAssertEqual(snapshot.timetables.map(\.id), [legacyID])
        XCTAssertEqual(snapshot.events[0].timetableID, legacyID)
    }

    func testSchemaZeroIsRejected() throws {
        let json = """
        {"schemaVersion":0,"events":[],"restaurants":[],"dishes":[],"meals":[]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try SnapshotStore.decode(json))
    }

    func testNegativeSchemaVersionIsRejected() throws {
        let json = """
        {"schemaVersion":-1,"events":[],"restaurants":[],"dishes":[],"meals":[]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try SnapshotStore.decode(json))
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

    func testSameUIDCanExistInTwoTimetablesWithoutIDCollision() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = CalendarEvent(
            id: "ics-shared",
            title: "大学英语",
            startsAt: start,
            endsAt: start.addingTimeInterval(3_600),
            source: .course,
            importedUID: "shared@example.edu"
        )
        var snapshot = AppSnapshot()

        let first = try snapshot.addTimetable(name: "主修", events: [parsed])
        let second = try snapshot.addTimetable(name: "辅修", events: [parsed])

        XCTAssertEqual(snapshot.timetables.map(\.id), [first.id, second.id])
        XCTAssertEqual(Set(snapshot.events.map(\.id)).count, 2)
        XCTAssertEqual(Set(snapshot.events.compactMap(\.timetableID)), [first.id, second.id])
    }

    func testReplacingTimetableIsScopedAndKeepsStableNamespacedIDs() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = CalendarEvent(
            id: "ics-shared",
            title: "原课程",
            startsAt: start,
            endsAt: start.addingTimeInterval(3_600),
            source: .course,
            importedUID: "shared@example.edu"
        )
        var snapshot = AppSnapshot()
        let first = try snapshot.addTimetable(name: "主修", events: [parsed])
        let second = try snapshot.addTimetable(name: "辅修", events: [parsed])
        let firstID = snapshot.events.first { $0.timetableID == first.id }!.id
        var changed = parsed
        changed.title = "更新课程"

        try snapshot.replaceTimetable(id: first.id, events: [changed])

        XCTAssertEqual(snapshot.events.first { $0.timetableID == first.id }?.id, firstID)
        XCTAssertEqual(snapshot.events.first { $0.timetableID == first.id }?.title, "更新课程")
        XCTAssertEqual(snapshot.events.first { $0.timetableID == second.id }?.title, "原课程")
    }

    func testDisabledAndDeletedTimetablesAreIsolated() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = AppSnapshot()
        let custom = CalendarEvent(title: "自定义安排", startsAt: start, endsAt: start.addingTimeInterval(1_800))
        snapshot.events = [custom]
        let first = try snapshot.addTimetable(name: "主修", events: [
            CalendarEvent(id: "first", title: "高数", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
        ])
        let second = try snapshot.addTimetable(name: "辅修", events: [
            CalendarEvent(id: "second", title: "英语", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
        ])

        snapshot.setTimetableEnabled(id: first.id, isEnabled: false)
        XCTAssertEqual(Set(snapshot.activeEvents.map(\.title)), ["自定义安排", "英语"])

        snapshot.removeTimetable(id: second.id)
        XCTAssertEqual(snapshot.events.map(\.title), ["自定义安排", "高数"])
        XCTAssertTrue(snapshot.timetables.contains { $0.id == first.id })
        XCTAssertFalse(snapshot.timetables.contains { $0.id == second.id })
    }

    func testRemovingEventUsesStableIDInsteadOfFilteredOffset() {
        let early = CalendarEvent(id: "early", title: "早", startsAt: Date(timeIntervalSince1970: 100), endsAt: Date(timeIntervalSince1970: 200))
        let unrelated = CalendarEvent(id: "unrelated", title: "其他日期", startsAt: Date(timeIntervalSince1970: 500), endsAt: Date(timeIntervalSince1970: 600))
        let late = CalendarEvent(id: "late", title: "晚", startsAt: Date(timeIntervalSince1970: 300), endsAt: Date(timeIntervalSince1970: 400))
        var snapshot = AppSnapshot()
        snapshot.events = [unrelated, late, early]

        snapshot.removeEvent(id: late.id)

        XCTAssertEqual(Set(snapshot.events.map(\.id)), ["unrelated", "early"])
    }

    func testFailedReplacementLeavesSnapshotUnchanged() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = AppSnapshot()
        let timetable = try snapshot.addTimetable(name: "主修", events: [
            CalendarEvent(id: "course", title: "课程", startsAt: start, endsAt: start.addingTimeInterval(3_600), source: .course)
        ])
        let before = snapshot

        XCTAssertThrowsError(try snapshot.replaceTimetable(id: UUID(), events: []))
        XCTAssertEqual(snapshot, before)
        XCTAssertEqual(snapshot.events(for: timetable.id).count, 1)
    }

    func testImportedDescriptionsAreNotPresentationNotes() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let course = CalendarEvent(title: "课程", startsAt: start, endsAt: start.addingTimeInterval(3_600), notes: "代码 CS101 · 第 1-16 周", source: .course)
        let custom = CalendarEvent(title: "安排", startsAt: start, endsAt: start.addingTimeInterval(3_600), notes: "带电脑")

        XCTAssertEqual(course.presentationNotes, "")
        XCTAssertEqual(custom.presentationNotes, "带电脑")
    }
}
