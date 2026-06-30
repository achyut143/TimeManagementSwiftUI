import SwiftUI
import SwiftData
import Foundation

enum RestraintLimitType: String, Codable, CaseIterable {
    case duration = "duration"
    case quantity = "quantity"

    var displayName: String {
        switch self {
        case .duration: return "Duration"
        case .quantity: return "Quantity"
        }
    }
}

struct RestraintTimeWindowInfo: Codable, Identifiable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int

    var timeString: String {
        let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}

@Model
class Restraint {
    var name: String
    var weekdays: [Int]         // empty = every day; 1=Sun…7=Sat
    var timeWindowsData: Data   // JSON-encoded [RestraintTimeWindowInfo] — these are RELEASE times
    var limitType: String       // RestraintLimitType.rawValue
    var awardedMinutes: Int     // minutes awarded per release window (duration-based)
    var quantityLimit: Double   // quantity awarded per release window (quantity-based)
    var quantityUnit: String    // e.g. "kcal"
    var isActive: Bool
    var createdAt: Date
    var colorName: String = "blue"          // default keeps existing records valid
    var iconName: String = "hand.raised.fill"

    @Relationship(deleteRule: .cascade, inverse: \RestraintInstance.restraint)
    var instances: [RestraintInstance] = []

    init(
        name: String,
        weekdays: [Int] = [],
        limitType: RestraintLimitType = .duration,
        awardedMinutes: Int = 30,
        quantityLimit: Double = 0,
        quantityUnit: String = "",
        timeWindows: [RestraintTimeWindowInfo] = [],
        colorName: String = "blue",
        iconName: String = "hand.raised.fill"
    ) {
        self.name = name
        self.weekdays = weekdays
        self.limitType = limitType.rawValue
        self.awardedMinutes = awardedMinutes
        self.quantityLimit = quantityLimit
        self.quantityUnit = quantityUnit
        self.isActive = true
        self.createdAt = Date()
        self.timeWindowsData = (try? JSONEncoder().encode(timeWindows)) ?? Data()
        self.colorName = colorName
        self.iconName = iconName
    }

    var displayColor: Color {
        switch colorName {
        case "indigo":  return .indigo
        case "purple":  return .purple
        case "pink":    return .pink
        case "red":     return .red
        case "orange":  return .orange
        case "green":   return .green
        case "teal":    return .teal
        case "cyan":    return .cyan
        default:        return .blue
        }
    }

    var timeWindows: [RestraintTimeWindowInfo] {
        get { (try? JSONDecoder().decode([RestraintTimeWindowInfo].self, from: timeWindowsData)) ?? [] }
        set { timeWindowsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var effectiveLimitType: RestraintLimitType {
        RestraintLimitType(rawValue: limitType) ?? .duration
    }

    var weekdayNames: String {
        if weekdays.isEmpty { return "Every day" }
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return weekdays.sorted().compactMap { wd -> String? in
            guard wd >= 1 && wd <= 7 else { return nil }
            return symbols[wd - 1]
        }.joined(separator: ", ")
    }

    func isScheduledOn(date: Date) -> Bool {
        if weekdays.isEmpty { return true }
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekdays.contains(weekday)
    }

    // Returns absolute Date values for all release windows across yesterday, today, tomorrow
    // so we can correctly find the surrounding interval even at midnight boundaries.
    private func allNearbyWindowDates(relativeTo date: Date) -> [Date] {
        let cal = Calendar.current
        var result: [Date] = []
        for offset in -7...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: date) else { continue }
            if isScheduledOn(date: day) {
                for w in timeWindows {
                    var comps = cal.dateComponents([.year, .month, .day], from: day)
                    comps.hour = w.hour
                    comps.minute = w.minute
                    comps.second = 0
                    if let d = cal.date(from: comps) { result.append(d) }
                }
            }
        }
        return result
    }

    // The release window just passed (last time you were allowed to use it)
    func lastReleaseWindow(at date: Date = Date()) -> Date? {
        allNearbyWindowDates(relativeTo: date).filter { $0 <= date }.max()
    }

    // The next upcoming release window
    func nextReleaseWindow(at date: Date = Date()) -> Date? {
        allNearbyWindowDates(relativeTo: date).filter { $0 > date }.min()
    }

    // 0.0 → 1.0: how far from last release window to next release window
    func holdProgress(at date: Date = Date()) -> Double {
        guard let last = lastReleaseWindow(at: date),
              let next = nextReleaseWindow(at: date) else { return 0 }
        let total = next.timeIntervalSince(last)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(last) / total, 0), 1)
    }

    func timeHeld(at date: Date = Date()) -> TimeInterval {
        guard let last = lastReleaseWindow(at: date) else { return 0 }
        return max(date.timeIntervalSince(last), 0)
    }

    func timeUntilRelease(at date: Date = Date()) -> TimeInterval {
        guard let next = nextReleaseWindow(at: date) else { return 0 }
        return max(next.timeIntervalSince(date), 0)
    }
}
