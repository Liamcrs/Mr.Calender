import Foundation

public enum HolidayKind: String, Codable, Sendable { case holiday, workday, festival }
public struct HolidayLabel: Equatable, Sendable { public let name: String; public let kind: HolidayKind; public init(name: String, kind: HolidayKind) { self.name = name; self.kind = kind } }

public enum HolidayProvider {
    public static func labels(on date: Date, calendar: Calendar = .current) -> [HolidayLabel] {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return [] }
        var labels: [HolidayLabel] = []
        if month == 1 && day == 1 { labels.append(.init(name: "元旦", kind: .holiday)) }
        if month == 2 && day == 17 && year == 2026 { labels.append(.init(name: "春节", kind: .holiday)) }
        if month == 4 && day == 5 && year == 2026 { labels.append(.init(name: "清明节", kind: .holiday)) }
        if month == 5 && day == 1 { labels.append(.init(name: "劳动节", kind: .holiday)) }
        if month == 6 && day == 19 && year == 2026 { labels.append(.init(name: "端午节", kind: .holiday)) }
        if month == 9 && day == 25 && year == 2026 { labels.append(.init(name: "中秋节", kind: .holiday)) }
        if month == 10 && day == 1 { labels.append(.init(name: "国庆节", kind: .holiday)) }
        if month == 12 && day == 25 { labels.append(.init(name: "圣诞节", kind: .festival)) }
        if month == 2 && day == 14 { labels.append(.init(name: "情人节", kind: .festival)) }
        if month == 10 && day == 31 { labels.append(.init(name: "万圣节", kind: .festival)) }
        if month == 11 && day == 26 { labels.append(.init(name: "感恩节", kind: .festival)) }
        if year == 2026 && month == 9 && day == 20 { labels.append(.init(name: "调休上班", kind: .workday)) }
        if year == 2026 && month == 10 && day == 10 { labels.append(.init(name: "调休上班", kind: .workday)) }
        return labels
    }
}
