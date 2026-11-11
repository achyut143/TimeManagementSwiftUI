import Foundation
import SwiftData

/// How a repeat task repeats. Tasks saved before weekly/monthly existed have
/// no kind stored and are read as `.days` ("every N days"), so they keep
/// working exactly as before.
enum RepeatKind: String, CaseIterable, Identifiable {
    case days, weekly, monthly
    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: return "Every N days"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

/// A task's repeat settings in one place.
///
/// `interval` is `Task.repeatAgain`: days for `.days`, weeks for `.weekly`,
/// months for `.monthly`. Any repeat task still has `repeatAgain != nil`, so
/// every existing "is this a habit?" check keeps working.
struct RepeatRule: Equatable {
    var kind: RepeatKind = .days
    var interval: Int = 1
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday. Empty = the task's own weekday.
    var weekdays: Set<Int> = []
    /// Days of the month, 1…31. Empty = the task's own day. A day the month
    /// doesn't have (e.g. 31 in April) falls on the month's last day.
    var monthDays: Set<Int> = []
    /// Last day it may repeat on (inclusive); nil = forever.
    var endDate: Date? = nil

    init(kind: RepeatKind = .days, interval: Int = 1, weekdays: Set<Int> = [], monthDays: Set<Int> = [], endDate: Date? = nil) {
        self.kind = kind
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.monthDays = monthDays
        self.endDate = endDate
    }

    /// nil when the task doesn't repeat.
    init?(task: Task) {
        guard let n = task.repeatAgain, n > 0 else { return nil }
        self.init(kind: RepeatKind(rawValue: task.repeatKindRaw ?? "") ?? .days,
                  interval: n,
                  weekdays: Set(task.repeatWeekdays),
                  monthDays: Set(task.repeatMonthDays),
                  endDate: task.repeatEndDate)
    }

    /// Writes these settings onto a task (nil rule = stop repeating).
    static func apply(_ rule: RepeatRule?, to task: Task) {
        guard let rule else {
            task.repeatAgain = nil
            task.repeatKindRaw = nil
            task.repeatWeekdays = []
            task.repeatMonthDays = []
            task.repeatEndDate = nil
            // The series ID stays, so the series knows it was turned off here.
            return
        }
        task.repeatAgain = rule.interval
        if task.repeatSeriesID == nil { task.repeatSeriesID = UUID() }
        // Leave plain "every N days" unset, like older tasks.
        task.repeatKindRaw = rule.kind == .days ? nil : rule.kind.rawValue
        task.repeatWeekdays = rule.kind == .weekly ? rule.weekdays.sorted() : []
        task.repeatMonthDays = rule.kind == .monthly ? rule.monthDays.sorted() : []
        task.repeatEndDate = rule.endDate.map { Calendar.current.startOfDay(for: $0) }
    }

    /// Repeats every day (missed days then don't roll over, as before).
    var isDaily: Bool {
        switch kind {
        case .days: return interval == 1
        case .weekly: return interval == 1 && weekdays.count == 7
        case .monthly: return false
        }
    }

    func isPastEnd(_ day: Date) -> Bool {
        guard let endDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: day) > cal.startOfDay(for: endDate)
    }

    /// Whether the repeat lands on `day`, counting from an occurrence on `anchor`.
    func occurs(on day: Date, anchor: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: day), a = cal.startOfDay(for: anchor)
        guard d > a, !isPastEnd(d) else { return false }

        switch kind {
        case .days:
            let diff = cal.dateComponents([.day], from: a, to: d).day ?? 0
            return diff % interval == 0

        case .weekly:
            let days = weekdays.isEmpty ? [cal.component(.weekday, from: a)] : weekdays
            guard days.contains(cal.component(.weekday, from: d)) else { return false }
            guard interval > 1 else { return true }
            let wa = cal.dateInterval(of: .weekOfYear, for: a)?.start ?? a
            let wd = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
            let weeks = (cal.dateComponents([.day], from: wa, to: wd).day ?? 0) / 7
            return weeks % interval == 0

        case .monthly:
            let wanted = monthDays.isEmpty ? [cal.component(.day, from: a)] : monthDays
            let dom = cal.component(.day, from: d)
            let last = cal.range(of: .day, in: .month, for: d)?.count ?? 31
            let hit = wanted.contains(dom) || (dom == last && wanted.contains { $0 > last })
            guard hit else { return false }
            guard interval > 1 else { return true }
            let ca = cal.dateComponents([.year, .month], from: a)
            let cd = cal.dateComponents([.year, .month], from: d)
            let months = ((cd.year ?? 0) - (ca.year ?? 0)) * 12 + ((cd.month ?? 0) - (ca.month ?? 0))
            return months % interval == 0
        }
    }

    /// The first day after `date` it repeats on, or nil past the end date.
    func next(after date: Date) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        // Long enough for "every 12 months"-style rules.
        for i in 1...(400 * max(1, kind == .monthly ? interval : 1)) {
            guard let day = cal.date(byAdding: .day, value: i, to: start) else { return nil }
            if isPastEnd(day) { return nil }
            if occurs(on: day, anchor: start) { return day }
        }
        return nil
    }

    // MARK: Text

    /// Short badge text next to the repeat icon: "3", "Wk", "Mo".
    var badge: String {
        switch kind {
        case .days: return "\(interval)"
        case .weekly: return interval == 1 ? "Wk" : "\(interval)w"
        case .monthly: return interval == 1 ? "Mo" : "\(interval)mo"
        }
    }

    /// "Every 2 days", "Weekly on Mon, Wed", "Every 2 months on 1, 15 · until Dec 31".
    var summary: String {
        var text: String
        switch kind {
        case .days:
            text = interval == 1 ? "Every day" : "Every \(interval) days"
        case .weekly:
            let names = Calendar.current.shortWeekdaySymbols
            let ordered = Self.weekOrder.filter { weekdays.contains($0) }
            let days = ordered.isEmpty ? "same weekday" : ordered.map { names[$0 - 1] }.joined(separator: ", ")
            text = (interval == 1 ? "Weekly" : "Every \(interval) weeks") + " on " + days
        case .monthly:
            let days = monthDays.isEmpty ? "same date" : monthDays.sorted().map(String.init).joined(separator: ", ")
            text = (interval == 1 ? "Monthly" : "Every \(interval) months") + " on " + days
        }
        if let endDate {
            text += " · until " + endDate.formatted(date: .abbreviated, time: .omitted)
        }
        return text
    }

    /// Weekdays in the order the user's calendar starts the week.
    static var weekOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

extension Task {
    var repeatRule: RepeatRule? { RepeatRule(task: self) }

    /// Average days between repeats, for habit stats and labels that think
    /// in days (weekly Mon/Wed/Fri ≈ 2, monthly on the 1st ≈ 30).
    var repeatGapDays: Int? {
        guard let rule = repeatRule else { return nil }
        switch rule.kind {
        case .days: return rule.interval
        case .weekly:
            let per = max(1, rule.weekdays.isEmpty ? 1 : rule.weekdays.count)
            return max(1, Int((Double(7 * rule.interval) / Double(per)).rounded()))
        case .monthly:
            let per = max(1, rule.monthDays.isEmpty ? 1 : rule.monthDays.count)
            return max(1, Int((Double(30 * rule.interval) / Double(per)).rounded()))
        }
    }

    /// Daily repeats don't roll a missed task over to tomorrow (tomorrow already has one).
    var isDailyRepeat: Bool { repeatRule?.isDaily ?? false }

    /// Copies the repeat settings onto another task (copies, splits, next occurrences).
    func copyRepeat(to other: Task) {
        other.repeatAgain = repeatAgain
        other.repeatKindRaw = repeatKindRaw
        other.repeatWeekdays = repeatWeekdays
        other.repeatMonthDays = repeatMonthDays
        other.repeatEndDate = repeatEndDate
        other.repeatSeriesID = repeatSeriesID
    }

    /// Groups a series: its ID, or the title for anything not migrated yet.
    var seriesKey: String { repeatSeriesID.map { "id:\($0.uuidString)" } ?? "title:\(title)" }

    var isInSeries: Bool { repeatSeriesID != nil }
}

/// Repeat series: every copy of a repeating task shares `repeatSeriesID`.
@MainActor
enum RepeatSeries {
    static let migrationKey = "repeat.seriesMigration.v1"

    /// One-time conversion on launch: gives every existing repeat task a
    /// series ID. Tasks with the same title (how they were linked before)
    /// share one ID. Nothing else needs converting: older tasks without a
    /// repeat kind already read as "every N days".
    static func migrateOnce(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        let changed = assignMissingIDs(context: context)
        UserDefaults.standard.set(true, forKey: migrationKey)
        if changed > 0 { print("Repeat series: linked \(changed) tasks") }
    }

    /// Gives repeat tasks without a series ID one: an existing series with the
    /// same title if there is one, otherwise a new one. Safe to run any time.
    @discardableResult
    static func assignMissingIDs(context: ModelContext, all: [Task]? = nil) -> Int {
        let tasks = all ?? ((try? context.fetch(FetchDescriptor<Task>())) ?? [])
        let missing = tasks.filter { $0.repeatAgain != nil && $0.repeatSeriesID == nil }
        guard !missing.isEmpty else { return 0 }
        var byTitle: [String: UUID] = [:]
        for t in tasks { if let id = t.repeatSeriesID, byTitle[t.title] == nil { byTitle[t.title] = id } }
        for t in missing {
            let id = byTitle[t.title] ?? UUID()
            byTitle[t.title] = id
            t.repeatSeriesID = id
        }
        try? context.save()
        return missing.count
    }

    /// Every task in the task's series (including it), oldest first.
    static func members(of task: Task, context: ModelContext) -> [Task] {
        guard let id = task.repeatSeriesID else { return [task] }
        let all = (try? context.fetch(FetchDescriptor<Task>(predicate: #Predicate<Task> { $0.repeatSeriesID == id }))) ?? []
        return all.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    enum DeleteScope { case thisOne, thisAndFuture, all }

    /// Counts for the delete prompt.
    static func counts(for task: Task, context: ModelContext) -> (future: Int, all: Int) {
        let m = members(of: task, context: context)
        let day = Calendar.current.startOfDay(for: task.date ?? Date())
        return (m.filter { ($0.date ?? .distantPast) >= day }.count, m.count)
    }

    /// Deletes this task, this and later ones (and stops the repeat there),
    /// or the whole series including its history.
    static func delete(_ task: Task, scope: DeleteScope, context: ModelContext) {
        let cal = Calendar.current
        let day = cal.startOfDay(for: task.date ?? Date())
        let series = members(of: task, context: context)
        switch scope {
        case .thisOne:
            RepeatScheduler.markFilled(task)
            context.delete(task)
        case .thisAndFuture:
            for t in series where (t.date.map { cal.startOfDay(for: $0) } ?? day) >= day {
                context.delete(t)
            }
            // Earlier ones end the day before, so nothing makes new copies.
            let lastDay = cal.date(byAdding: .day, value: -1, to: day) ?? day
            for t in series where (t.date.map { cal.startOfDay(for: $0) } ?? day) < day && t.repeatAgain != nil {
                if t.repeatEndDate == nil || t.repeatEndDate! > lastDay { t.repeatEndDate = lastDay }
            }
        case .all:
            for t in series { context.delete(t) }
        }
        try? context.save()
    }

    /// After editing one task's repeat settings, later copies follow them.
    static func applyRuleToFuture(from task: Task, context: ModelContext) {
        guard let date = task.date else { return }
        for t in members(of: task, context: context) where t !== task && (t.date ?? .distantPast) > date {
            task.copyRepeat(to: t)
        }
        try? context.save()
    }
}

/// Puts repeat tasks onto a day when it's opened, so a day you open already
/// has its habits even if yesterday's weren't checked off.
///
/// For each series it takes the most recent task before that day as the
/// template. It adds a copy when the template still repeats, isn't turned off
/// (red), the rule lands on the day, the end date hasn't passed, and the
/// series hasn't already had that day (a copy deleted or moved away doesn't
/// come back).
@MainActor
enum RepeatScheduler {
    private static let filledKey = "repeat.filledDays.v1"

    nonisolated private static func dayKey(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated private static var filled: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: filledKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: filledKey) }
    }

    /// Remembers that the task's series has had its day, so it isn't re-added.
    nonisolated static func markFilled(_ task: Task, on day: Date? = nil) {
        guard let d = day ?? task.date, task.repeatAgain != nil else { return }
        var f = filled
        f[task.seriesKey + "|" + dayKey(d)] = dayKey(d)
        filled = f
    }

    /// Returns how many tasks were added.
    @discardableResult
    static func fill(day: Date, context: ModelContext) -> Int {
        let cal = Calendar.current
        let target = cal.startOfDay(for: day)
        // Never back-fill past days; you see those as missed in the tracker.
        guard target >= cal.startOfDay(for: Date()) else { return 0 }

        let all = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        RepeatSeries.assignMissingIDs(context: context, all: all)
        let dated = all.filter { $0.date != nil && $0.repeatSeriesID != nil }
        let targetKey = dayKey(target)
        var done = filled
        // Forget days older than 60 days.
        let cutoff = dayKey(cal.date(byAdding: .day, value: -60, to: target) ?? target)
        done = done.filter { $0.value >= cutoff }

        let onTarget = Set(dated.filter { cal.isDate($0.date!, inSameDayAs: target) }.map(\.seriesKey))
        for key in onTarget { done[key + "|" + targetKey] = targetKey }

        // Latest task per series strictly before the target day.
        var latest: [String: Task] = [:]
        for t in dated where t.date! < target {
            let key = t.seriesKey
            if let cur = latest[key] {
                if t.date! > cur.date! || (cal.isDate(t.date!, inSameDayAs: cur.date!) && !t.reassign && cur.reassign) {
                    latest[key] = t
                }
            } else {
                latest[key] = t
            }
        }

        var added = 0
        for (key, template) in latest {
            guard done[key + "|" + targetKey] == nil,
                  !template.reassign,
                  let rule = template.repeatRule,
                  let anchor = template.date,
                  rule.occurs(on: target, anchor: anchor) else { continue }
            TaskRepeater.makeOccurrence(of: template, on: target, context: context)
            done[key + "|" + targetKey] = targetKey
            added += 1
        }
        filled = done
        if added > 0 {
            try? context.save()
            NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        }
        return added
    }

    /// Today's fill; called when the app opens or becomes active.
    static func fillToday(context: ModelContext) {
        fill(day: Date(), context: context)
    }
}

/// The name each habit (repeat series) goes by on the habit screens.
///
/// It's the title of the series' most recent task, so renaming a habit
/// renames it everywhere. Two different series with the same title get
/// "Name (2)", "Name (3)" so their stats stay apart. Tasks not in a series
/// use their title, exactly as before.
final class HabitNames: @unchecked Sendable {
    static let shared = HabitNames()
    private let lock = NSLock()
    private var bySeries: [UUID: String] = [:]

    func name(for id: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return bySeries[id]
    }

    /// Recomputes every series' name from the tasks.
    func rebuild(from tasks: [Task]) {
        var latest: [UUID: Task] = [:]
        var first: [UUID: Date] = [:]
        for t in tasks {
            guard let id = t.repeatSeriesID else { continue }
            let d = t.date ?? .distantPast
            if let cur = latest[id], (cur.date ?? .distantPast) >= d {} else { latest[id] = t }
            if let f = first[id], f <= d {} else { first[id] = d }
        }
        // Same title: the older series keeps the plain name.
        let byTitle = Dictionary(grouping: latest.keys) { latest[$0]!.title }
        var names: [UUID: String] = [:]
        for (title, ids) in byTitle {
            let ordered = ids.sorted { (first[$0] ?? .distantPast, $0.uuidString) < (first[$1] ?? .distantPast, $1.uuidString) }
            for (i, id) in ordered.enumerated() {
                names[id] = i == 0 ? title : "\(title) (\(i + 1))"
            }
        }
        lock.lock(); bySeries = names; lock.unlock()
    }

    func rebuild(context: ModelContext) {
        rebuild(from: (try? context.fetch(FetchDescriptor<Task>())) ?? [])
    }
}

extension Task {
    /// See `HabitNames`.
    var habitName: String {
        guard let id = repeatSeriesID else { return title }
        return HabitNames.shared.name(for: id) ?? title
    }

    /// Same habit: same series, or the same title when either isn't in one.
    func isSameHabit(as other: Task) -> Bool {
        if let a = repeatSeriesID, let b = other.repeatSeriesID { return a == b }
        return title == other.title
    }
}
