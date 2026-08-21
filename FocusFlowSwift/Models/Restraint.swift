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

// Two opposite shapes living under one "Rule" umbrella:
//  - .restraint ("Don't"): restrained by default, released periodically for a
//    small allowance — e.g. Instagram. This is the original, pre-existing
//    behavior, and is the default for every row so existing data is
//    unaffected.
//  - .practice ("Do"): the mirror image — free by default, prompted
//    periodically to actively do something for a duration — e.g. "read every
//    3 hours for 15 minutes."
enum RestraintKind: String, Codable, CaseIterable, Identifiable {
    case restraint
    case practice

    var id: String { rawValue }
    var displayName: String { self == .restraint ? "Restraint" : "Practice" }
    var pluralName: String { self == .restraint ? "Restraints" : "Practices" }
    var subtitle: String { self == .restraint ? "Something to limit" : "Something to do regularly" }
    var defaultIcon: String { self == .restraint ? "hand.raised.fill" : "arrow.triangle.2.circlepath" }
    // Wording for the two log states — "Pass/Fail" reads oddly for a Practice.
    var passWord: String { self == .restraint ? "Pass" : "Done" }
    var failWord: String { self == .restraint ? "Fail" : "Skipped" }
}

struct RestraintTimeWindowInfo: Codable, Identifiable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    // Per-window award override; nil = use the restraint's default award.
    // Optional so existing encoded windows (with no such key) decode as nil.
    var awardOverride: Double? = nil

    var timeString: String {
        let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h, minute, ampm)
    }
}

@Model
class Restraint {
    // Stable identity for notification scheduling etc. Default-generated so
    // existing rows (created before this field existed) just get a fresh one.
    var id: UUID = UUID()
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
    var showInFocusWidget: Bool = true      // default true keeps existing restraints visible
    // If true, an unused award from the most recent resolved window carries
    // into the next one. Default false = unchanged behavior for existing restraints.
    var rolloverEnabled: Bool = false
    // Default "restraint" so every row created before this field existed —
    // i.e. all current data — keeps behaving exactly as it always has.
    var kindRaw: String = RestraintKind.restraint.rawValue

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
        iconName: String = "hand.raised.fill",
        kind: RestraintKind = .restraint
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
        self.kindRaw = kind.rawValue
    }

    var kind: RestraintKind {
        get { RestraintKind(rawValue: kindRaw) ?? .restraint }
        set { kindRaw = newValue.rawValue }
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

    // A restraint with no release windows is tracked as pure daily abstinence
    // (one pass/fail per scheduled day) instead of window-by-window release.
    var isAbstinence: Bool { timeWindows.isEmpty }

    // The award for a specific window: its own override if set, else the
    // restraint's default.
    func effectiveAward(for window: RestraintTimeWindowInfo) -> Double {
        if let override = window.awardOverride { return override }
        return effectiveLimitType == .duration ? Double(awardedMinutes) : quantityLimit
    }

    // The award for one specific logged occurrence: that instance's own
    // override first (set per-day in the Log sheet), then its matching
    // template window's override, then the restraint's flat default.
    func effectiveAward(for instance: RestraintInstance) -> Double {
        if let override = instance.awardOverride { return override }
        if let window = timeWindows.first(where: { $0.hour == instance.windowHour && $0.minute == instance.windowMinute }) {
            return effectiveAward(for: window)
        }
        return effectiveLimitType == .duration ? Double(awardedMinutes) : quantityLimit
    }

    // Unused award carried in from the single most recent *resolved* (not
    // pending) prior instance — intentionally a one-hop carry, not a deep
    // ledger, to keep this predictable. 0 when rollover is off or there's
    // nothing prior to carry from.
    func rolloverIntoWindow(hour: Int, minute: Int, on date: Date) -> Double {
        guard rolloverEnabled else { return 0 }
        let cal = Calendar.current
        var targetComps = cal.dateComponents([.year, .month, .day], from: date)
        targetComps.hour = hour
        targetComps.minute = minute
        guard let targetDate = cal.date(from: targetComps) else { return 0 }

        let priorCandidates: [(RestraintInstance, Date)] = instances.compactMap { inst in
            guard !inst.isPending else { return nil }
            var c = cal.dateComponents([.year, .month, .day], from: inst.date)
            c.hour = inst.windowHour
            c.minute = inst.windowMinute
            guard let d = cal.date(from: c), d < targetDate else { return nil }
            return (inst, d)
        }
        guard let (prior, _) = priorCandidates.max(by: { $0.1 < $1.1 }) else { return 0 }
        guard let priorWindow = timeWindows.first(where: { $0.hour == prior.windowHour && $0.minute == prior.windowMinute }) else { return 0 }
        let leftover = effectiveAward(for: priorWindow) - prior.awardedUsed
        return max(0, leftover)
    }

    // Consecutive scheduled days/windows resolved as Pass, walking back from
    // the most recently *fully resolved* day (today only counts once all its
    // windows have actually happened). Abstinence restraints use their single
    // daily record instead of a per-window array.
    func currentPassStreak(asOf date: Date = Date()) -> Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: date)

        if isScheduledOn(date: day) {
            let windowsToCheck = isAbstinence ? [RestraintTimeWindowInfo(hour: 23, minute: 59)] : timeWindows
            let allWindowsPast = windowsToCheck.allSatisfy { w in
                var c = cal.dateComponents([.year, .month, .day], from: day)
                c.hour = w.hour
                c.minute = w.minute
                guard let wd = cal.date(from: c) else { return true }
                return wd <= date
            }
            if !allWindowsPast {
                day = cal.date(byAdding: .day, value: -1, to: day) ?? day
            }
        }

        var streak = 0
        while streak < 3650 {
            if isScheduledOn(date: day) {
                let dayPassed: Bool
                if isAbstinence {
                    let rec = instances.first { cal.isDate($0.date, inSameDayAs: day) }
                    dayPassed = rec?.status == "pass"
                } else {
                    guard !timeWindows.isEmpty else { break }
                    let dayInstances = timeWindows.map { w in
                        instances.first { cal.isDate($0.date, inSameDayAs: day) && $0.windowHour == w.hour && $0.windowMinute == w.minute }
                    }
                    dayPassed = dayInstances.allSatisfy { $0?.status == "pass" }
                }
                guard dayPassed else { break }
                streak += 1
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
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
