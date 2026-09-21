import Foundation

public enum WorkoutRecordSource: String, Codable, Equatable, Sendable {
    case manual
    case appleHealth

    public var title: String {
        switch self {
        case .manual: return "手动"
        case .appleHealth: return "Apple 健康"
        }
    }
}

public struct WorkoutRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: WorkoutKind
    public var minutes: Int
    public var distanceKM: Double
    public var source: WorkoutRecordSource
    public var date: Date

    public var title: String { kind.title }

    public init(id: String, kind: WorkoutKind, minutes: Int, distanceKM: Double,
                source: WorkoutRecordSource, date: Date) {
        self.id = id
        self.kind = kind
        self.minutes = minutes
        self.distanceKM = distanceKM
        self.source = source
        self.date = date
    }
}

public enum WorkoutHistory {
    public static func records(manual: [ManualWorkout], health: [WorkoutRecord],
                               from start: Date, to end: Date) -> [WorkoutRecord] {
        let manualRecords = manual.map {
            WorkoutRecord(
                id: "manual-\($0.id.uuidString)",
                kind: $0.kind,
                minutes: $0.minutes,
                distanceKM: $0.distanceKM,
                source: .manual,
                date: $0.date
            )
        }

        var seen = Set<String>()
        return (health + manualRecords)
            .filter { $0.date >= start && $0.date < end }
            .sorted {
                if $0.date == $1.date { return $0.id < $1.id }
                return $0.date > $1.date
            }
            .filter { seen.insert($0.id).inserted }
    }
}
