import Foundation

public enum ICSCheckFailure: Error { case failed(String) }

public func runICSChecks() throws {
    let zone = TimeZone(identifier: "Asia/Shanghai")!
    let iso = ISO8601DateFormatter()
    func date(_ text: String) -> Date { iso.date(from: text)! }
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw ICSCheckFailure.failed(message) }
    }
    func parse(_ body: String, from: String = "2026-09-01T00:00:00+08:00", to: String = "2026-10-01T00:00:00+08:00") throws -> ICSImportResult {
        try ICSParser.parse("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(body)END:VCALENDAR\r\n", from: date(from), to: date(to), timeZone: zone)
    }

    let weekly = try parse("BEGIN:VEVENT\r\nUID:math\r\nDTSTART;TZID=Asia/Shanghai:20260907T080000\r\nDTEND;TZID=Asia/Shanghai:20260907T093000\r\nRRULE:FREQ=WEEKLY;COUNT=3;BYDAY=MO\r\nSUMMARY:高等数学\r\nEND:VEVENT\r\n")
    try require(weekly.events.count == 3, "weekly COUNT")
    try require(weekly.events[0].startsAt == date("2026-09-07T08:00:00+08:00"), "TZID conversion")
    try require(weekly.events.allSatisfy { $0.source == .course && $0.reminderMinutes == 15 }, "course metadata")

    let history = try parse("BEGIN:VEVENT\r\nUID:history\r\nDTSTART;TZID=Asia/Shanghai:20260803T140000\r\nDTEND;TZID=Asia/Shanghai:20260803T150000\r\nRRULE:FREQ=WEEKLY;COUNT=8;BYDAY=MO\r\nEXDATE;TZID=Asia/Shanghai:20260907T140000\r\nRDATE;TZID=Asia/Shanghai:20260909T140000\r\nSUMMARY:历史\r\nEND:VEVENT\r\n")
    try require(history.events.map(\.startsAt) == [date("2026-09-09T14:00:00+08:00"), date("2026-09-14T14:00:00+08:00"), date("2026-09-21T14:00:00+08:00")], "COUNT/EXDATE/RDATE")

    let overrides = "BEGIN:VEVENT\r\nUID:s\r\nDTSTART;TZID=Asia/Shanghai:20260907T080000\r\nDTEND;TZID=Asia/Shanghai:20260907T090000\r\nRRULE:FREQ=WEEKLY;COUNT=3\r\nSUMMARY:原课\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:s\r\nRECURRENCE-ID;TZID=Asia/Shanghai:20260914T080000\r\nDTSTART;TZID=Asia/Shanghai:20260914T100000\r\nDTEND;TZID=Asia/Shanghai:20260914T110000\r\nSUMMARY:调课\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:s\r\nRECURRENCE-ID;TZID=Asia/Shanghai:20260921T080000\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\n"
    let first = try parse(overrides), second = try parse(overrides)
    try require(first.events.count == 2 && first.events[1].title == "调课", "override/cancellation")
    try require(first.events.map(\.id) == second.events.map(\.id), "stable IDs")

    let allDay = try parse("BEGIN:VEVENT\r\nUID:day\r\nDTSTART;VALUE=DATE:20260911\r\nDTEND;VALUE=DATE:20260913\r\nSUMMARY:校庆\r\nEND:VEVENT\r\n")
    try require(allDay.events[0].isAllDay && allDay.events[0].endsAt == date("2026-09-13T00:00:00+08:00"), "all-day exclusive end")

    let folded = try parse("BEGIN:VEVENT\r\nUID:fold\r\nDTSTART:20260908T100000\r\nDTEND:20260908T110000\r\nSUMMARY:计算机\r\n 网络\r\nDESCRIPTION:一\\n二\\\\末\r\nEND:VEVENT\r\n")
    try require(folded.events[0].title == "计算机网络" && folded.events[0].notes == "一\n二\\末", "folded UTF-8/escaping")

    let ny = TimeZone(identifier: "America/New_York")!
    let dstText = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:dst\r\nDTSTART;TZID=America/New_York:20260307T090000\r\nDTEND;TZID=America/New_York:20260307T100000\r\nRRULE:FREQ=DAILY;COUNT=3\r\nSUMMARY:DST\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let dst = try ICSParser.parse(dstText, from: date("2026-03-06T00:00:00-05:00"), to: date("2026-03-11T00:00:00-04:00"), timeZone: ny)
    try require(dst.events.map(\.startsAt) == [date("2026-03-07T09:00:00-05:00"), date("2026-03-08T09:00:00-04:00"), date("2026-03-09T09:00:00-04:00")], "DST wall clock")

    let cancelled = try parse("BEGIN:VEVENT\r\nUID:gone\r\nSTATUS:CANCELLED\r\nEND:VEVENT\r\n")
    try require(cancelled.events.isEmpty && cancelled.importedUIDs == ["gone"], "cancelled UID")

    do { _ = try parse("BEGIN:VEVENT\r\nUID:bad\r\nDTSTART;TZID=Mars/Olympus:20260908T100000\r\nDTEND;TZID=Mars/Olympus:20260908T110000\r\nEND:VEVENT\r\n"); throw ICSCheckFailure.failed("unknown TZID accepted") } catch is ICSParser.ParseError {}
    do { _ = try parse("BEGIN:VEVENT\r\nUID:bad\r\nDTSTART:20260908T100000\r\nDTEND:20260908T110000\r\nRRULE:FREQ=MONTHLY\r\nEND:VEVENT\r\n"); throw ICSCheckFailure.failed("unsupported RRULE accepted") } catch is ICSParser.ParseError {}
    do { _ = try parse("BEGIN:VEVENT\r\nUID:bad\r\nDTSTART:20260230T100000\r\nDTEND:20260230T110000\r\nEND:VEVENT\r\n"); throw ICSCheckFailure.failed("invalid date accepted") } catch is ICSParser.ParseError {}
    do { _ = try parse("BEGIN:VEVENT\r\nUID:far\r\nDTSTART:00010101T000000\r\nDTEND:00010101T010000\r\nRRULE:FREQ=DAILY;UNTIL=99991231T235959Z\r\nEND:VEVENT\r\n"); throw ICSCheckFailure.failed("malicious rule was not bounded") } catch is ICSParser.ParseError {}
}
