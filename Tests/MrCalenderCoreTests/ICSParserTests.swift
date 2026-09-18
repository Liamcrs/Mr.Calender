import XCTest
@testable import MrCalenderCore

final class ICSParserTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func parse(_ body: String,
                       from: String = "2026-09-01T00:00:00+08:00",
                       to: String = "2026-10-01T00:00:00+08:00") throws -> ICSImportResult {
        try ICSParser.parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(body)END:VCALENDAR\r\n",
                            from: date(from), to: date(to), timeZone: shanghai)
    }

    func testWeeklyCourseKeepsWallClockAndMetadata() throws {
        let result = try parse("""
        BEGIN:VEVENT\r
        UID:math@example.edu\r
        DTSTART;TZID=Asia/Shanghai:20260907T080000\r
        DTEND;TZID=Asia/Shanghai:20260907T093000\r
        RRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO;WKST=MO\r
        SUMMARY:高等数学\r
        LOCATION:教学楼 A101\r
        DESCRIPTION:第一章\\n请预习\r
        END:VEVENT\r

        """)
        XCTAssertEqual(result.events.count, 3)
        XCTAssertEqual(result.events.map(\.title), ["高等数学", "高等数学", "高等数学"])
        XCTAssertEqual(result.events.first?.startsAt, date("2026-09-07T08:00:00+08:00"))
        XCTAssertEqual(result.events.first?.endsAt, date("2026-09-07T09:30:00+08:00"))
        XCTAssertEqual(result.events.first?.location, "教学楼 A101")
        XCTAssertEqual(result.events.first?.notes, "第一章\n请预习")
        XCTAssertEqual(result.events.first?.source, .course)
        XCTAssertEqual(result.events.first?.importedUID, "math@example.edu")
        XCTAssertEqual(result.events.first?.reminderMinutes, 15)
        XCTAssertEqual(result.importedUIDs, ["math@example.edu"])
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testFoldedUTF8AndEscapedValues() throws {
        let result = try parse("""
        BEGIN:VEVENT\r
        UID:folded\r
        DTSTART:20260908T100000\r
        DTEND:20260908T110000\r
        SUMMARY:计算机\r
         网络\r
        LOCATION:楼一\\,房间二\\;东\r
        DESCRIPTION:第一行\\n第二行\\\\结束\r
        END:VEVENT\r

        """)
        XCTAssertEqual(result.events[0].title, "计算机网络")
        XCTAssertEqual(result.events[0].location, "楼一,房间二;东")
        XCTAssertEqual(result.events[0].notes, "第一行\n第二行\\结束")
    }

    func testTZIDUTCAndAllDayExclusiveEnd() throws {
        let result = try parse("""
        BEGIN:VEVENT\r
        UID:ny\r
        DTSTART;TZID=America/New_York:20260910T090000\r
        DTEND;TZID=America/New_York:20260910T100000\r
        SUMMARY:Remote\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:utc\r
        DTSTART:20260910T010000Z\r
        DTEND:20260910T020000Z\r
        SUMMARY:UTC\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:day\r
        DTSTART;VALUE=DATE:20260911\r
        DTEND;VALUE=DATE:20260913\r
        SUMMARY:校庆\r
        END:VEVENT\r

        """)
        let events = Dictionary(uniqueKeysWithValues: result.events.map { ($0.importedUID!, $0) })
        XCTAssertEqual(events["ny"]?.startsAt, date("2026-09-10T09:00:00-04:00"))
        XCTAssertEqual(events["utc"]?.startsAt, date("2026-09-10T01:00:00Z"))
        XCTAssertEqual(events["day"]?.startsAt, date("2026-09-11T00:00:00+08:00"))
        XCTAssertEqual(events["day"]?.endsAt, date("2026-09-13T00:00:00+08:00"))
        XCTAssertTrue(events["day"]!.isAllDay)
    }

    func testCountIsAppliedBeforeHorizonAndExdateWithRdate() throws {
        let result = try parse("""
        BEGIN:VEVENT\r
        UID:history\r
        DTSTART;TZID=Asia/Shanghai:20260803T140000\r
        DTEND;TZID=Asia/Shanghai:20260803T150000\r
        RRULE:FREQ=WEEKLY;COUNT=8;BYDAY=MO\r
        EXDATE;TZID=Asia/Shanghai:20260907T140000\r
        RDATE;TZID=Asia/Shanghai:20260909T140000\r
        SUMMARY:历史\r
        END:VEVENT\r

        """)
        XCTAssertEqual(result.events.map(\.startsAt), [
            date("2026-09-09T14:00:00+08:00"), date("2026-09-14T14:00:00+08:00"),
            date("2026-09-21T14:00:00+08:00")
        ])
    }

    func testOverrideAndCancelledOccurrencePreserveOriginalIdentity() throws {
        let body = """
        BEGIN:VEVENT\r
        UID:series\r
        DTSTART;TZID=Asia/Shanghai:20260907T080000\r
        DTEND;TZID=Asia/Shanghai:20260907T090000\r
        RRULE:FREQ=WEEKLY;COUNT=3\r
        SUMMARY:原课\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:series\r
        RECURRENCE-ID;TZID=Asia/Shanghai:20260914T080000\r
        DTSTART;TZID=Asia/Shanghai:20260914T100000\r
        DTEND;TZID=Asia/Shanghai:20260914T110000\r
        SUMMARY:调课\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:series\r
        RECURRENCE-ID;TZID=Asia/Shanghai:20260921T080000\r
        STATUS:CANCELLED\r
        END:VEVENT\r

        """
        let first = try parse(body)
        let second = try parse(body)
        XCTAssertEqual(first.events.count, 2)
        XCTAssertEqual(first.events.map(\.startsAt), [date("2026-09-07T08:00:00+08:00"), date("2026-09-14T10:00:00+08:00")])
        XCTAssertEqual(first.events[1].title, "调课")
        XCTAssertEqual(first.events.map(\.id), second.events.map(\.id))
        XCTAssertNotEqual(first.events[0].id, first.events[1].id)
    }

    func testCancelledSeriesStillReturnsUID() throws {
        let result = try parse("""
        BEGIN:VEVENT\r
        UID:cancelled\r
        DTSTART:20260908T100000\r
        DTEND:20260908T110000\r
        STATUS:CANCELLED\r
        SUMMARY:取消\r
        END:VEVENT\r

        """)
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.importedUIDs, ["cancelled"])
    }

    func testRejectsUnknownTZIDAndUnsupportedRulesTransactionally() {
        XCTAssertThrowsError(try parse("""
        BEGIN:VEVENT\r
        UID:bad-zone\r
        DTSTART;TZID=Mars/Olympus:20260908T100000\r
        DTEND;TZID=Mars/Olympus:20260908T110000\r
        SUMMARY:Bad\r
        END:VEVENT\r

        """))
        for rule in ["FREQ=MONTHLY", "FREQ=WEEKLY;BYSETPOS=1", "FREQ=WEEKLY;BYDAY=1MO"] {
            XCTAssertThrowsError(try parse("""
            BEGIN:VEVENT\r
            UID:bad-rule\r
            DTSTART:20260908T100000\r
            DTEND:20260908T110000\r
            RRULE:\(rule)\r
            SUMMARY:Bad\r
            END:VEVENT\r

            """))
        }
    }

    func testRejectsMalformedAndInvalidValues() {
        let bodies = [
            "BEGIN:VEVENT\r\nDTSTART:20260908T100000\r\nDTEND:20260908T110000\r\nEND:VEVENT\r\n",
            "BEGIN:VEVENT\r\nUID:x\r\nDTSTART:20260230T100000\r\nDTEND:20260230T110000\r\nEND:VEVENT\r\n",
            "BEGIN:VEVENT\r\nUID:x\r\nDTSTART:20260908T120000\r\nDTEND:20260908T110000\r\nEND:VEVENT\r\n",
            "not an ics file\r\n"
        ]
        for body in bodies { XCTAssertThrowsError(try parse(body)) }
    }

    func testDailyDSTKeepsLocalWallClock() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:dst\r\nDTSTART;TZID=America/New_York:20260307T090000\r\nDTEND;TZID=America/New_York:20260307T100000\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:DST\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let result = try ICSParser.parse(text, from: date("2026-03-06T00:00:00-05:00"), to: date("2026-03-11T00:00:00-04:00"), timeZone: ny)
        XCTAssertEqual(result.events.map(\.startsAt), [
            date("2026-03-07T09:00:00-05:00"), date("2026-03-08T09:00:00-04:00"), date("2026-03-09T09:00:00-04:00")
        ])
    }

    func testMaliciousRulesAreBounded() {
        let far = "BEGIN:VEVENT\r\nUID:far\r\nDTSTART:00010101T000000\r\nDTEND:00010101T010000\r\nRRULE:FREQ=DAILY;UNTIL=99991231T235959Z\r\nSUMMARY:Far\r\nEND:VEVENT\r\n"
        XCTAssertThrowsError(try parse(far))
        XCTAssertThrowsError(try parse("BEGIN:VEVENT\r\nUID:zero\r\nDTSTART:20260901T000000\r\nDTEND:20260901T010000\r\nRRULE:FREQ=DAILY;INTERVAL=0\r\nSUMMARY:Zero\r\nEND:VEVENT\r\n"))
    }
}
