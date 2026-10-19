import Foundation
import SwiftData
import SwiftUI

// Impulse & Daily Planner. Impulse time lives on ordinary Tasks (see the
// impulse* fields on Task); this file holds the supporting models and the
// rules that decide planned vs unplanned, budget use, day-plan status and
// wake/sleep marks.

// MARK: - Impulse types

@Model
final class ImpulseType {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#E4572E"
    var planBeforeHours: Double = 12
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(name: String, colorHex: String, planBeforeHours: Double, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.planBeforeHours = planBeforeHours
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var color: Color { Color(hex: colorHex) }

    // Regular tasks are drawn gray, so no gray here — impulse tasks must stand out.
    static let palette: [String] = [
        "#E4572E", "#F2A541", "#D7263D", "#C2185B", "#8E44AD",
        "#3F51B5", "#0097A7", "#2E9E5B", "#A0522D", "#FF6F91"
    ]
}

/// One row per budget change. A month uses the last version that took
/// effect before the month ended, so editing the budget never rewrites
/// past months.
@Model
final class ImpulseBudgetVersion {
    var monthlyHours: Double = 15
    var effectiveFrom: Date = Date()

    init(monthlyHours: Double, effectiveFrom: Date = Date()) {
        self.monthlyHours = monthlyHours
        self.effectiveFrom = effectiveFrom
    }
}

// MARK: - Goals by period

enum GoalPeriod: String, CaseIterable, Identifiable {
    case day, week, month, quarter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "Quarter"
        }
    }

    /// The period a goal of this period can link up to.
    var parent: GoalPeriod? {
        switch self {
        case .day: return .week
        case .week: return .month
        case .month: return .quarter
        case .quarter: return nil
        }
    }

    func start(for date: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .day: return date.startOfDay
        case .week: return PlanDates.weekStart(for: date)
        case .month: return cal.date(from: cal.dateComponents([.year, .month], from: date))!
        case .quarter: return PlanDates.quarterStart(for: date)
        }
    }

    func next(after start: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .day: return cal.date(byAdding: .day, value: 1, to: start)!
        case .week: return cal.date(byAdding: .day, value: 7, to: start)!
        case .month: return cal.date(byAdding: .month, value: 1, to: start)!
        case .quarter: return cal.date(byAdding: .month, value: 3, to: start)!
        }
    }

    func previous(before start: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .day: return cal.date(byAdding: .day, value: -1, to: start)!
        case .week: return cal.date(byAdding: .day, value: -7, to: start)!
        case .month: return cal.date(byAdding: .month, value: -1, to: start)!
        case .quarter: return cal.date(byAdding: .month, value: -3, to: start)!
        }
    }

    func label(for start: Date) -> String {
        switch self {
        case .day: return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week: return "Week of \(start.formatted(.dateTime.month(.abbreviated).day()))"
        case .month: return start.formatted(.dateTime.month(.wide).year())
        case .quarter: return PlanDates.quarterLabel(for: start)
        }
    }
}

enum GoalStatus: String {
    case open, done, notDone, carried
}

@Model
final class PeriodGoal {
    var id: UUID = UUID()
    var title: String = ""
    var periodRaw: String = GoalPeriod.day.rawValue
    var periodStart: Date = Date()
    var statusRaw: String = GoalStatus.open.rawValue
    var parentGoalID: UUID? = nil
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(title: String, period: GoalPeriod, periodStart: Date, sortOrder: Int = 0, parentGoalID: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.periodRaw = period.rawValue
        self.periodStart = period.start(for: periodStart)
        self.sortOrder = sortOrder
        self.parentGoalID = parentGoalID
        self.createdAt = Date()
    }

    var period: GoalPeriod { GoalPeriod(rawValue: periodRaw) ?? .day }
    var status: GoalStatus {
        get { GoalStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    var isDone: Bool { status == .done }
}

// MARK: - Day plan

@Model
final class PlannerDay {
    var date: Date = Date()   // start of day
    var breakfast: String = ""
    var lunch: String = ""
    var dinner: String = ""
    var breakfastTime: Date? = nil
    var lunchTime: Date? = nil
    var dinnerTime: Date? = nil
    var breakfastEaten: Bool = false
    var lunchEaten: Bool = false
    var dinnerEaten: Bool = false
    var noImpulseDay: Bool = false
    var wakeActual: Date? = nil
    var sleepActual: Date? = nil
    var createdAt: Date = Date()

    init(date: Date) {
        self.date = date.startOfDay
        self.createdAt = Date()
    }

    var mealsPlanned: Int {
        [breakfast, lunch, dinner].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    static func fetch(for date: Date, context: ModelContext) -> PlannerDay? {
        let day = date.startOfDay
        var descriptor = FetchDescriptor<PlannerDay>(predicate: #Predicate { $0.date == day })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    static func getOrCreate(for date: Date, context: ModelContext) -> PlannerDay {
        if let existing = fetch(for: date, context: context) { return existing }
        let day = PlannerDay(date: date)
        context.insert(day)
        return day
    }
}

// MARK: - Sleep schedule

/// Changing the schedule adds a version; each day is judged against the
/// version active on that day, so results stay separate per schedule.
@Model
final class SleepScheduleVersion {
    var wakeMinutes: Int = 6 * 60 + 30     // minutes after midnight
    var sleepMinutes: Int = 22 * 60 + 30   // under 12:00 means after midnight
    var windowMinutes: Int = 15
    var effectiveFrom: Date = Date()       // start of day
    var createdAt: Date = Date()

    init(wakeMinutes: Int, sleepMinutes: Int, windowMinutes: Int, effectiveFrom: Date) {
        self.wakeMinutes = wakeMinutes
        self.sleepMinutes = sleepMinutes
        self.windowMinutes = windowMinutes
        self.effectiveFrom = effectiveFrom.startOfDay
        self.createdAt = Date()
    }

    var label: String {
        "\(PlannerRules.clock(sleepMinutes)) / \(PlannerRules.clock(wakeMinutes))"
    }
}

enum SleepMark {
    case onTime, early, late, missing, pending

    var text: String {
        switch self {
        case .onTime: return "On time"
        case .early: return "Early"
        case .late: return "Late"
        case .missing: return "Missing"
        case .pending: return "?"
        }
    }

    var color: Color {
        switch self {
        case .onTime: return .green
        case .early: return .blue
        case .late: return .orange
        case .missing: return .red
        case .pending: return .secondary
        }
    }
}

// MARK: - Impulse rules

enum BudgetState {
    case within, nearLimit, over

    var text: String {
        switch self {
        case .within: return "Within budget"
        case .nearLimit: return "Near limit"
        case .over: return "Over budget"
        }
    }

    var color: Color {
        switch self {
        case .within: return .green
        case .nearLimit: return .orange
        case .over: return .red
        }
    }
}

struct BudgetSummary {
    var budgetMinutes: Double?        // nil = no budget set
    var usedMinutes: Double = 0
    var committedMinutes: Double = 0
    var byType: [UUID: Double] = [:]  // used + committed per impulse type

    var remainingMinutes: Double { max(0, (budgetMinutes ?? 0) - usedMinutes - committedMinutes) }

    var fraction: Double {
        guard let budget = budgetMinutes, budget > 0 else { return 0 }
        return (usedMinutes + committedMinutes) / budget
    }

    var state: BudgetState {
        if fraction > 1 { return .over }
        if fraction >= 0.8 { return .nearLimit }
        return .within
    }
}

enum ImpulseRules {
    /// What a task looked like before an edit, so `reconcile` can tell a
    /// move earlier from a move later.
    struct Snapshot {
        let typeID: UUID?
        let start: Date?
        let scheduledMinutes: Double

        init(_ task: Task) {
            typeID = task.impulseTypeID
            start = ImpulseRules.startDate(of: task)
            scheduledMinutes = ImpulseRules.scheduledMinutes(of: task)
        }
    }

    static func minutes(from time: String) -> Int? {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func span(from start: Int, to end: Int) -> Double {
        Double(end >= start ? end - start : 24 * 60 - start + end)
    }

    static func startDate(of task: Task) -> Date? {
        guard let date = task.date, let mins = minutes(from: task.startTime) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: mins, to: date.startOfDay)
    }

    static func scheduledMinutes(of task: Task) -> Double {
        if let s = minutes(from: task.startTime), let e = minutes(from: task.endTime) {
            return span(from: s, to: e)
        }
        return task.elapsedTime ?? task.timeSpent ?? 0
    }

    /// Scheduled length, or start → logged actual end when the impulse overran.
    static func actualMinutes(of task: Task) -> Double {
        if let s = minutes(from: task.startTime), let actual = task.actualEndTime, let e = minutes(from: actual) {
            return span(from: s, to: e)
        }
        return scheduledMinutes(of: task)
    }

    static func endDate(of task: Task) -> Date? {
        if let start = startDate(of: task) {
            return start.addingTimeInterval(actualMinutes(of: task) * 60)
        }
        // Untimed: treat it as over once its day is over.
        guard let date = task.date else { return nil }
        return Calendar.current.date(byAdding: .day, value: 1, to: date.startOfDay)
    }

    static func isSkipped(_ task: Task) -> Bool { task.notCompleted && !task.completed }

    static func isPlanned(checkedAt: Date, start: Date, planBeforeHours: Double) -> Bool {
        checkedAt < start && checkedAt <= start.addingTimeInterval(-planBeforeHours * 3600)
    }

    /// Re-applies the planned rule after a task is created or edited.
    /// - New task, new/changed impulse type, or moved earlier: checked from scratch with `now` as the created time.
    /// - Moved later or shortened: a planned task stays planned.
    /// - Lengthened: the extra minutes are planned only if they pass the rule now.
    static func reconcile(_ task: Task, before: Snapshot?, types: [ImpulseType], now: Date = Date()) {
        guard let typeID = task.impulseTypeID else {
            task.impulseCheckedAt = nil
            task.impulsePlannedMinutes = nil
            task.actualEndTime = nil
            return
        }
        let planBefore = types.first { $0.id == typeID }?.planBeforeHours ?? 0
        let start = startDate(of: task)
        let scheduled = scheduledMinutes(of: task)

        func checkFresh() {
            task.impulseCheckedAt = now
            if let start, isPlanned(checkedAt: now, start: start, planBeforeHours: planBefore) {
                task.impulsePlannedMinutes = scheduled
            } else {
                task.impulsePlannedMinutes = 0
            }
        }

        guard let before, before.typeID == typeID, task.impulseCheckedAt != nil,
              let oldStart = before.start, let start else {
            checkFresh()
            return
        }

        let wasPlanned = (task.impulsePlannedMinutes ?? 0) > 0
        if start < oldStart || !wasPlanned && start != oldStart {
            checkFresh()
            return
        }
        if scheduled > before.scheduledMinutes, wasPlanned,
           isPlanned(checkedAt: now, start: start, planBeforeHours: planBefore) {
            task.impulsePlannedMinutes = scheduled
        }
    }

    /// Planned share of a task's time. A broken no-impulse day makes all of it unplanned.
    static func plannedMinutes(of task: Task, noImpulseDay: Bool = false) -> Double {
        guard !noImpulseDay else { return 0 }
        return min(task.impulsePlannedMinutes ?? 0, actualMinutes(of: task))
    }

    static func unplannedMinutes(of task: Task, noImpulseDay: Bool = false) -> Double {
        actualMinutes(of: task) - plannedMinutes(of: task, noImpulseDay: noImpulseDay)
    }

    static func isPlannedLabel(_ task: Task, noImpulseDay: Bool = false) -> Bool {
        plannedMinutes(of: task, noImpulseDay: noImpulseDay) > 0
    }

    /// Carries the impulse type onto a repeat/rollover copy, checked fresh.
    static func inherit(from source: Task, to copy: Task, context: ModelContext) {
        guard let typeID = source.impulseTypeID else { return }
        copy.impulseTypeID = typeID
        let types = (try? context.fetch(FetchDescriptor<ImpulseType>())) ?? []
        reconcile(copy, before: nil, types: types)
    }

    // MARK: Budget

    static func monthStart(for date: Date) -> Date { GoalPeriod.month.start(for: date) }

    static func budgetMinutes(forMonthOf date: Date, versions: [ImpulseBudgetVersion]) -> Double? {
        let end = GoalPeriod.month.next(after: monthStart(for: date))
        let version = versions.filter { $0.effectiveFrom < end }.max { $0.effectiveFrom < $1.effectiveFrom }
        guard let hours = version?.monthlyHours, hours > 0 else { return nil }
        return hours * 60
    }

    static func tasks(_ tasks: [Task], inMonthOf date: Date) -> [Task] {
        let start = monthStart(for: date)
        let end = GoalPeriod.month.next(after: start)
        return tasks.filter { t in
            guard t.impulseTypeID != nil, let d = t.date else { return false }
            return d >= start && d < end
        }
    }

    static func budget(forMonthOf date: Date, tasks all: [Task], versions: [ImpulseBudgetVersion], now: Date = Date()) -> BudgetSummary {
        var summary = BudgetSummary(budgetMinutes: budgetMinutes(forMonthOf: date, versions: versions))
        for task in tasks(all, inMonthOf: date) where !isSkipped(task) {
            let mins = actualMinutes(of: task)
            if task.completed || (endDate(of: task).map { $0 <= now } ?? false) {
                summary.usedMinutes += mins
            } else {
                summary.committedMinutes += mins
            }
            if let id = task.impulseTypeID { summary.byType[id, default: 0] += mins }
        }
        return summary
    }
}

// MARK: - Day plan & sleep rules

struct PlannerDayStatus {
    let dayGoals: [PeriodGoal]
    let mealsPlanned: Int
    let impulseTasks: [Task]
    let noImpulseDay: Bool

    var goalsDone: Bool { dayGoals.count >= 3 }
    var mealsDone: Bool { mealsPlanned == 3 }
    var impulsesDone: Bool { noImpulseDay || !impulseTasks.isEmpty }
    var isPlanned: Bool { goalsDone && mealsDone && impulsesDone }
    var noImpulseBroken: Bool { noImpulseDay && impulseTasks.contains { !ImpulseRules.isSkipped($0) } }

    var plannedImpulseMinutes: Double {
        impulseTasks.filter { !ImpulseRules.isSkipped($0) }
            .reduce(0) { $0 + ImpulseRules.plannedMinutes(of: $1, noImpulseDay: noImpulseDay) }
    }
}

enum PlannerRules {
    static func dayStatus(for date: Date, days: [PlannerDay], goals: [PeriodGoal], impulseTasks: [Task]) -> PlannerDayStatus {
        let day = date.startOfDay
        let planner = days.first { $0.date == day }
        return PlannerDayStatus(
            dayGoals: goals.filter { $0.periodRaw == GoalPeriod.day.rawValue && $0.periodStart == day && $0.status != .carried },
            mealsPlanned: planner?.mealsPlanned ?? 0,
            impulseTasks: impulseTasks.filter { $0.date.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false },
            noImpulseDay: planner?.noImpulseDay ?? false
        )
    }

    static func goals(_ goals: [PeriodGoal], period: GoalPeriod, containing date: Date) -> [PeriodGoal] {
        let start = period.start(for: date)
        return goals
            .filter { $0.periodRaw == period.rawValue && $0.periodStart == start && $0.status != .carried }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(byAdding: .minute, value: minutes, to: Date().startOfDay)!
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func activeSchedule(on date: Date, versions: [SleepScheduleVersion]) -> SleepScheduleVersion? {
        let day = date.startOfDay
        return versions.filter { $0.effectiveFrom <= day }
            .max { ($0.effectiveFrom, $0.createdAt) < ($1.effectiveFrom, $1.createdAt) }
    }

    static func wakeTarget(on date: Date, _ v: SleepScheduleVersion) -> Date {
        Calendar.current.date(byAdding: .minute, value: v.wakeMinutes, to: date.startOfDay)!
    }

    /// A target before noon (e.g. 12:30 am) belongs to the night that started on `date`.
    static func sleepTarget(on date: Date, _ v: SleepScheduleVersion) -> Date {
        let offset = v.sleepMinutes < 12 * 60 ? v.sleepMinutes + 24 * 60 : v.sleepMinutes
        return Calendar.current.date(byAdding: .minute, value: offset, to: date.startOfDay)!
    }

    /// Going to bed at 12:40 am counts for the previous evening.
    static func sleepDay(for moment: Date) -> Date {
        let day = moment.startOfDay
        return Calendar.current.component(.hour, from: moment) < 12 ? PlanDates.adding(-1, to: day) : day
    }

    static func mark(actual: Date?, target: Date, window: Int, now: Date = Date()) -> SleepMark {
        guard let actual else {
            return now > target.addingTimeInterval(Double(window) * 60) ? .missing : .pending
        }
        let diff = actual.timeIntervalSince(target) / 60
        if abs(diff) <= Double(window) { return .onTime }
        return diff < 0 ? .early : .late
    }

    static func wakeMark(_ day: PlannerDay?, on date: Date, versions: [SleepScheduleVersion], now: Date = Date()) -> SleepMark? {
        guard let v = activeSchedule(on: date, versions: versions) else { return nil }
        return mark(actual: day?.wakeActual, target: wakeTarget(on: date, v), window: v.windowMinutes, now: now)
    }

    static func sleepMark(_ day: PlannerDay?, on date: Date, versions: [SleepScheduleVersion], now: Date = Date()) -> SleepMark? {
        guard let v = activeSchedule(on: date, versions: versions) else { return nil }
        return mark(actual: day?.sleepActual, target: sleepTarget(on: date, v), window: v.windowMinutes, now: now)
    }

    static func formatMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) m"
    }

    static func formatHours(_ minutes: Double) -> String {
        let h = minutes / 60
        return h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h)
    }
}
