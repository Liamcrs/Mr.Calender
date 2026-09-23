import Foundation

public enum TimetableError: Error, LocalizedError, Equatable {
    case emptyName
    case timetableNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyName: return "课表名称不能为空"
        case .timetableNotFound: return "找不到需要更新的课表"
        }
    }
}

public extension CalendarEvent {
    var presentationNotes: String { source == .custom ? notes : "" }
}

public extension AppSnapshot {
    var activeEvents: [CalendarEvent] {
        let enabled = Set(timetables.filter(\.isEnabled).map(\.id))
        return events.filter { event in
            event.source == .custom || event.timetableID.map(enabled.contains) == true
        }
    }

    func events(for timetableID: UUID) -> [CalendarEvent] {
        events.filter { $0.timetableID == timetableID }
    }

    @discardableResult
    mutating func addTimetable(name: String, events importedEvents: [CalendarEvent], importedAt: Date = Date()) throws -> Timetable {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TimetableError.emptyName }
        let timetable = Timetable(name: normalized, importedAt: importedAt)
        timetables.append(timetable)
        events.append(contentsOf: namespaced(importedEvents, for: timetable.id))
        return timetable
    }

    mutating func replaceTimetable(id: UUID, events importedEvents: [CalendarEvent], importedAt: Date = Date()) throws {
        guard let index = timetables.firstIndex(where: { $0.id == id }) else {
            throw TimetableError.timetableNotFound
        }
        events.removeAll { $0.timetableID == id }
        events.append(contentsOf: namespaced(importedEvents, for: id))
        timetables[index].importedAt = importedAt
    }

    mutating func setTimetableEnabled(id: UUID, isEnabled: Bool) {
        guard let index = timetables.firstIndex(where: { $0.id == id }) else { return }
        timetables[index].isEnabled = isEnabled
    }

    mutating func removeTimetable(id: UUID) {
        timetables.removeAll { $0.id == id }
        events.removeAll { $0.timetableID == id }
    }

    mutating func removeEvent(id: String) {
        events.removeAll { $0.id == id }
    }

    private func namespaced(_ importedEvents: [CalendarEvent], for timetableID: UUID) -> [CalendarEvent] {
        importedEvents.map { event in
            var value = event
            value.id = "timetable-\(timetableID.uuidString)-\(event.id)"
            value.timetableID = timetableID
            return value
        }
    }
}
