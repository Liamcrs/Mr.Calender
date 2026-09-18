import Foundation

public struct ICSImportResult: Sendable {
    public let events: [CalendarEvent]
    public let importedUIDs: Set<String>
    public let warnings: [String]
    public init(events: [CalendarEvent], importedUIDs: Set<String>, warnings: [String]) {
        self.events = events; self.importedUIDs = importedUIDs; self.warnings = warnings
    }
}

public enum ICSParser {
    public enum ParseError: Error, LocalizedError, Equatable {
        case invalid(String)
        public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }

    private struct Property { var name: String; var parameters: [String: String]; var value: String }
    private struct RawEvent { var properties: [Property] }
    private struct Stamp { var date: Date; var allDay: Bool; var zone: TimeZone; var components: DateComponents }
    private struct Rule { var frequency: String; var interval: Int; var count: Int?; var until: Date?; var weekdays: [Int]?; var weekStart: Int }
    private struct Template { var uid: String; var start: Stamp; var end: Stamp; var title: String; var location: String; var notes: String; var status: String; var rule: Rule?; var exdates: Set<Date>; var rdates: [Stamp] }

    private static let maxInputBytes = 5_000_000, maxRawEvents = 5_000, maxIterations = 100_000, maxOutput = 10_000

    public static func parse(_ text: String, from: Date, to: Date, timeZone: TimeZone = .current) throws -> ICSImportResult {
        guard from < to else { throw ParseError.invalid("Import horizon must have a positive duration") }
        guard text.utf8.count <= maxInputBytes else { throw ParseError.invalid("ICS input is too large") }
        let raw = try readEvents(text)
        var imported = Set<String>(), grouped: [String: [RawEvent]] = [:]
        for event in raw {
            let uid = try required("UID", in: event).value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { throw ParseError.invalid("VEVENT has an empty UID") }
            imported.insert(uid); grouped[uid, default: []].append(event)
        }
        var output: [CalendarEvent] = []
        for uid in grouped.keys.sorted() {
            let group = grouped[uid]!
            let masters = group.filter { property("RECURRENCE-ID", in: $0) == nil }
            guard masters.count == 1 else { throw ParseError.invalid("UID \(uid) must have exactly one master VEVENT") }
            let masterRaw = masters[0]
            if value("STATUS", in: masterRaw).uppercased() == "CANCELLED" { continue }
            let master = try makeTemplate(masterRaw, uid: uid, defaultZone: timeZone)
            var overrides: [Date: RawEvent] = [:]
            for item in group.filter({ property("RECURRENCE-ID", in: $0) != nil }) {
                let recurrence = try parseStamp(required("RECURRENCE-ID", in: item), defaultZone: timeZone)
                guard overrides[recurrence.date] == nil else { throw ParseError.invalid("Duplicate RECURRENCE-ID for UID \(uid)") }
                overrides[recurrence.date] = item
            }
            let expansionEnd = overrides.keys.max().map { max(to, $0.addingTimeInterval(1)) } ?? to
            var occurrences = try occurrenceDates(for: master, horizonEnd: expansionEnd)
            occurrences.append(contentsOf: master.rdates.map(\.date))
            occurrences = Array(Set(occurrences)).sorted()
            let occurrenceSet = Set(occurrences)
            guard overrides.keys.allSatisfy(occurrenceSet.contains) else { throw ParseError.invalid("RECURRENCE-ID does not identify an occurrence for UID \(uid)") }
            for original in occurrences where !master.exdates.contains(original) {
                let rawOverride = overrides[original]
                if let rawOverride, value("STATUS", in: rawOverride).uppercased() == "CANCELLED" { continue }
                let event: CalendarEvent
                if let rawOverride {
                    event = try makeOverride(rawOverride, master: master, original: original, defaultZone: timeZone)
                } else {
                    let duration = master.end.date.timeIntervalSince(master.start.date)
                    event = build(master: master, original: original, start: original,
                                  end: master.start.allDay ? addDays(original, count: daySpan(master), zone: master.start.zone) : original.addingTimeInterval(duration))
                }
                if event.startsAt < to && event.endsAt > from { output.append(event) }
                guard output.count <= maxOutput else { throw ParseError.invalid("ICS expands to too many events") }
            }
        }
        output.sort { $0.startsAt == $1.startsAt ? $0.id < $1.id : $0.startsAt < $1.startsAt }
        return ICSImportResult(events: output, importedUIDs: imported,
                               warnings: ["Recurring events were expanded only within the supplied import horizon."])
    }

    private static func readEvents(_ text: String) throws -> [RawEvent] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard normalized.contains("BEGIN:VCALENDAR") else { throw ParseError.invalid("Missing VCALENDAR") }
        var lines: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.first == " " || line.first == "\t"), !lines.isEmpty { lines[lines.count - 1] += String(line.dropFirst()) }
            else { lines.append(line) }
        }
        var events: [RawEvent] = [], current: [Property]? = nil, sawEnd = false
        for line in lines where !line.isEmpty {
            if line.uppercased() == "BEGIN:VEVENT" { guard current == nil else { throw ParseError.invalid("Nested VEVENT") }; current = []; continue }
            if line.uppercased() == "END:VEVENT" { guard let properties = current else { throw ParseError.invalid("Unexpected END:VEVENT") }; events.append(.init(properties: properties)); current = nil; continue }
            if line.uppercased() == "END:VCALENDAR" { sawEnd = true }
            if current != nil { current!.append(try parseProperty(line)) }
        }
        guard current == nil, sawEnd, !events.isEmpty else { throw ParseError.invalid("Malformed or empty VCALENDAR") }
        guard events.count <= maxRawEvents else { throw ParseError.invalid("Too many VEVENT entries") }
        return events
    }

    private static func parseProperty(_ line: String) throws -> Property {
        guard let colon = line.firstIndex(of: ":") else { throw ParseError.invalid("Malformed content line") }
        let head = line[..<colon].split(separator: ";", omittingEmptySubsequences: false)
        guard let first = head.first, !first.isEmpty else { throw ParseError.invalid("Missing property name") }
        var params: [String: String] = [:]
        for item in head.dropFirst() {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { throw ParseError.invalid("Malformed property parameter") }
            params[pair[0].uppercased()] = pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return Property(name: first.uppercased(), parameters: params, value: String(line[line.index(after: colon)...]))
    }

    private static func property(_ name: String, in event: RawEvent) -> Property? { event.properties.first { $0.name == name } }
    private static func properties(_ name: String, in event: RawEvent) -> [Property] { event.properties.filter { $0.name == name } }
    private static func required(_ name: String, in event: RawEvent) throws -> Property { guard let p = property(name, in: event) else { throw ParseError.invalid("VEVENT is missing \(name)") }; return p }
    private static func value(_ name: String, in event: RawEvent) -> String { property(name, in: event)?.value ?? "" }

    private static func makeTemplate(_ raw: RawEvent, uid: String, defaultZone: TimeZone) throws -> Template {
        if property("DURATION", in: raw) != nil { throw ParseError.invalid("DURATION is not supported; provide DTEND") }
        let start = try parseStamp(required("DTSTART", in: raw), defaultZone: defaultZone)
        let end = try parseStamp(required("DTEND", in: raw), defaultZone: defaultZone)
        guard end.date >= start.date, end.date > start.date else { throw ParseError.invalid("VEVENT has a non-positive duration") }
        guard start.allDay == end.allDay else { throw ParseError.invalid("DTSTART and DTEND value types differ") }
        let rule = try property("RRULE", in: raw).map { try parseRule($0.value, start: start) }
        let exdates = try Set(properties("EXDATE", in: raw).flatMap { try parseDateList($0, defaultZone: defaultZone).map(\.date) })
        let rdates = try properties("RDATE", in: raw).flatMap { try parseDateList($0, defaultZone: defaultZone) }
        return Template(uid: uid, start: start, end: end, title: unescape(value("SUMMARY", in: raw)), location: unescape(value("LOCATION", in: raw)), notes: unescape(value("DESCRIPTION", in: raw)), status: value("STATUS", in: raw), rule: rule, exdates: exdates, rdates: rdates)
    }

    private static func makeOverride(_ raw: RawEvent, master: Template, original: Date, defaultZone: TimeZone) throws -> CalendarEvent {
        let start = try property("DTSTART", in: raw).map { try parseStamp($0, defaultZone: defaultZone) } ?? master.start
        let actualStart = property("DTSTART", in: raw) == nil ? original : start.date
        let actualEnd: Date
        if let p = property("DTEND", in: raw) { actualEnd = try parseStamp(p, defaultZone: defaultZone).date }
        else { actualEnd = actualStart.addingTimeInterval(master.end.date.timeIntervalSince(master.start.date)) }
        guard actualEnd > actualStart else { throw ParseError.invalid("Override has a non-positive duration") }
        var changed = master
        if property("SUMMARY", in: raw) != nil { changed.title = unescape(value("SUMMARY", in: raw)) }
        if property("LOCATION", in: raw) != nil { changed.location = unescape(value("LOCATION", in: raw)) }
        if property("DESCRIPTION", in: raw) != nil { changed.notes = unescape(value("DESCRIPTION", in: raw)) }
        return build(master: changed, original: original, start: actualStart, end: actualEnd)
    }

    private static func build(master: Template, original: Date, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(id: stableID(uid: master.uid, original: original), title: master.title, startsAt: start, endsAt: end,
                      isAllDay: master.start.allDay, location: master.location, notes: master.notes, source: .course,
                      importedUID: master.uid, reminderMinutes: 15)
    }

    private static func parseStamp(_ p: Property, defaultZone: TimeZone) throws -> Stamp {
        let allDay = p.parameters["VALUE"]?.uppercased() == "DATE" || (p.value.count == 8 && !p.value.contains("T"))
        let hasZ = p.value.hasSuffix("Z")
        let zone: TimeZone
        if hasZ { zone = TimeZone(secondsFromGMT: 0)! }
        else if let identifier = p.parameters["TZID"] { guard let found = TimeZone(identifier: identifier) else { throw ParseError.invalid("Unknown TZID: \(identifier)") }; zone = found }
        else { zone = defaultZone }
        let raw = hasZ ? String(p.value.dropLast()) : p.value
        let pattern = allDay ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
        guard raw.count == (allDay ? 8 : 15) else { throw ParseError.invalid("Invalid date/time: \(p.value)") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone; formatter.dateFormat = pattern; formatter.isLenient = false
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { throw ParseError.invalid("Invalid date/time: \(p.value)") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let units: Set<Calendar.Component> = allDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute, .second]
        return Stamp(date: date, allDay: allDay, zone: zone, components: calendar.dateComponents(units, from: date))
    }

    private static func parseDateList(_ p: Property, defaultZone: TimeZone) throws -> [Stamp] {
        try p.value.split(separator: ",", omittingEmptySubsequences: false).map { part in var copy = p; copy.value = String(part); return try parseStamp(copy, defaultZone: defaultZone) }
    }

    private static func parseRule(_ text: String, start: Stamp) throws -> Rule {
        var fields: [String: String] = [:]
        let allowed: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "WKST"]
        for piece in text.split(separator: ";") {
            let pair = piece.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, allowed.contains(pair[0].uppercased()), fields[pair[0].uppercased()] == nil else { throw ParseError.invalid("Unsupported or malformed RRULE field") }
            fields[pair[0].uppercased()] = pair[1].uppercased()
        }
        guard let frequency = fields["FREQ"], frequency == "DAILY" || frequency == "WEEKLY" else { throw ParseError.invalid("Only DAILY and WEEKLY RRULE frequencies are supported") }
        let interval = try positiveInt(fields["INTERVAL"] ?? "1", name: "INTERVAL")
        let count = try fields["COUNT"].map { try positiveInt($0, name: "COUNT") }
        let until: Date? = try fields["UNTIL"].map { value in let p = Property(name: "UNTIL", parameters: start.allDay ? ["VALUE": "DATE"] : [:], value: value); return try parseStamp(p, defaultZone: start.zone).date }
        if count != nil && until != nil { throw ParseError.invalid("RRULE cannot contain both COUNT and UNTIL") }
        let map = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let weekdays: [Int]? = try fields["BYDAY"].map { try $0.split(separator: ",").map { token in guard let day = map[String(token)] else { throw ParseError.invalid("Unsupported BYDAY value") }; return day } }
        if frequency == "DAILY" && weekdays != nil { throw ParseError.invalid("BYDAY is supported only for WEEKLY rules") }
        guard let weekStart = map[fields["WKST"] ?? "MO"] else { throw ParseError.invalid("Invalid WKST") }
        return Rule(frequency: frequency, interval: interval, count: count, until: until, weekdays: weekdays, weekStart: weekStart)
    }

    private static func positiveInt(_ text: String, name: String) throws -> Int { guard let n = Int(text), n > 0, n <= maxIterations else { throw ParseError.invalid("Invalid \(name)") }; return n }

    private static func occurrenceDates(for template: Template, horizonEnd: Date) throws -> [Date] {
        guard let rule = template.rule else { return [template.start.date] }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = template.start.zone
        var results: [Date] = [], iterations = 0, cursor = template.start.date
        let bydays = Set(rule.weekdays ?? [calendar.component(.weekday, from: template.start.date)])
        func weekStart(_ date: Date) -> Date {
            let weekday = calendar.component(.weekday, from: date)
            let offset = (weekday - rule.weekStart + 7) % 7
            return calendar.date(byAdding: .day, value: -offset, to: date)!
        }
        let firstWeek = weekStart(template.start.date)
        while true {
            iterations += 1; guard iterations <= maxIterations else { throw ParseError.invalid("RRULE expansion exceeds safe iteration bound") }
            if cursor >= template.start.date {
                let days = calendar.dateComponents([.day], from: template.start.date, to: cursor).day ?? 0
                let weeks = (calendar.dateComponents([.day], from: firstWeek, to: weekStart(cursor)).day ?? 0) / 7
                let matches = rule.frequency == "DAILY" ? days % rule.interval == 0 : weeks % rule.interval == 0 && bydays.contains(calendar.component(.weekday, from: cursor))
                if matches {
                    if let until = rule.until, cursor > until { break }
                    results.append(cursor)
                    if let count = rule.count, results.count >= count { break }
                }
            }
            if rule.count == nil, rule.until == nil, cursor >= horizonEnd { break }
            if let until = rule.until, cursor > until { break }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { throw ParseError.invalid("Date recurrence overflow") }
            cursor = next
        }
        return results
    }

    private static func daySpan(_ t: Template) -> Int { var c = Calendar(identifier: .gregorian); c.timeZone = t.start.zone; return c.dateComponents([.day], from: t.start.date, to: t.end.date).day ?? 1 }
    private static func addDays(_ date: Date, count: Int, zone: TimeZone) -> Date { var c = Calendar(identifier: .gregorian); c.timeZone = zone; return c.date(byAdding: .day, value: count, to: date)! }
    private static func unescape(_ value: String) -> String { value.replacingOccurrences(of: "\\n", with: "\n", options: .caseInsensitive).replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\") }
    private static func stableID(uid: String, original: Date) -> String {
        let input = "\(uid)\u{1f}\(Int64((original.timeIntervalSince1970 * 1000).rounded()))"
        var hash: UInt64 = 14695981039346656037
        for byte in input.utf8 { hash ^= UInt64(byte); hash &*= 1099511628211 }
        return "ics-" + String(hash, radix: 16)
    }
}
