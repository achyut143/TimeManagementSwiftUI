import Foundation
import SwiftData
import SwiftUI
import UserNotifications

// Food control: plan food breaks the day before, log unplanned food, wait out
// cravings, and track cheats, calories and money.

// MARK: - Break template

/// A recurring food break, e.g. "Lunch at 12:00". Each day's plan starts
/// from these; a day can then add or remove its own breaks.
@Model
final class FoodBreak {
    var id: UUID = UUID()
    var name: String = ""
    var icon: String = "fork.knife"
    /// Minutes after midnight.
    var minutes: Int = 12 * 60
    /// Calendar weekdays it applies to (1 = Sunday … 7 = Saturday).
    var weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]
    var createdAt: Date = Date()

    init(name: String, icon: String, minutes: Int, weekdays: [Int] = [1, 2, 3, 4, 5, 6, 7]) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.minutes = minutes
        self.weekdays = weekdays
        self.createdAt = Date()
    }

    func applies(to date: Date) -> Bool {
        weekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    func time(on day: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: day.startOfDay)!
    }

    static let icons = ["fork.knife", "cup.and.saucer.fill", "mug.fill", "takeoutbag.and.cup.and.straw.fill",
                        "carrot.fill", "leaf.fill", "birthday.cake.fill", "wineglass.fill", "waterbottle.fill",
                        "sun.horizon.fill", "sun.max.fill", "moon.stars.fill"]
}

// MARK: - Entries

enum FoodEntryKind: String { case planned, unplanned }

enum FoodEntryStatus: String {
    case pending, eaten, swapped, skipped

    var label: String {
        switch self {
        case .pending: return "Not yet"
        case .eaten: return "Ate as planned"
        case .swapped: return "Ate something else"
        case .skipped: return "Skipped"
        }
    }
}

/// One food item on one day: either a planned break or unplanned food.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    /// Start of the day it belongs to.
    var day: Date = Date()
    /// Break time for planned food; when it was eaten for unplanned food.
    var time: Date = Date()
    var kindRaw: String = FoodEntryKind.planned.rawValue
    var statusRaw: String = FoodEntryStatus.pending.rawValue
    var breakID: UUID?
    var breakName: String = ""
    var icon: String = "fork.knife"
    /// The planned food (or what was eaten, for unplanned food).
    var food: String = ""
    var calories: Double?
    var cost: Double?
    /// When the food text was last set. Planned on time = before the day began.
    var plannedAt: Date?
    /// What was eaten instead, when the plan wasn't followed.
    var actualFood: String = ""
    var actualCalories: Double?
    var actualCost: Double?
    var eatenAt: Date?
    var trigger: String = ""
    /// 1 (not hungry) … 5 (very hungry); 0 = not recorded.
    var hunger: Int = 0
    var note: String = ""
    /// When a snoozed break now starts; `time` keeps the planned time.
    var snoozedUntil: Date?
    var snoozeCount: Int = 0
    var createdAt: Date = Date()

    init(day: Date, time: Date, kind: FoodEntryKind, breakID: UUID? = nil, breakName: String, icon: String, food: String = "") {
        self.id = UUID()
        self.day = day.startOfDay
        self.time = time
        self.kindRaw = kind.rawValue
        self.breakID = breakID
        self.breakName = breakName
        self.icon = icon
        self.food = food
        self.createdAt = Date()
    }

    var kind: FoodEntryKind { FoodEntryKind(rawValue: kindRaw) ?? .planned }
    /// The break's time after any snooze.
    var effectiveTime: Date { snoozedUntil ?? time }
    var status: FoodEntryStatus {
        get { FoodEntryStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var isUnplanned: Bool { kind == .unplanned }
    var hasPlan: Bool { !food.trimmingCharacters(in: .whitespaces).isEmpty }
    var wasConsumed: Bool { status == .eaten || status == .swapped }

    /// Planned before the day started (i.e. the day before or earlier).
    var plannedOnTime: Bool {
        guard kind == .planned, hasPlan, let plannedAt else { return false }
        return plannedAt < day
    }

    var eatenFood: String { status == .swapped ? actualFood : food }

    var eatenCalories: Double {
        guard wasConsumed else { return 0 }
        return (status == .swapped ? actualCalories : calories) ?? 0
    }

    var eatenCost: Double {
        guard wasConsumed else { return 0 }
        return (status == .swapped ? actualCost : cost) ?? 0
    }
}

/// A craving that was waited out (resisted) or given in to.
@Model
final class FoodCraving {
    var id: UUID = UUID()
    var date: Date = Date()
    var trigger: String = ""
    var resisted: Bool = true
    var waitedSeconds: Int = 0

    init(date: Date, trigger: String, resisted: Bool, waitedSeconds: Int) {
        self.id = UUID()
        self.date = date
        self.trigger = trigger
        self.resisted = resisted
        self.waitedSeconds = waitedSeconds
    }
}

// MARK: - Settings

/// Stored in UserDefaults so the floating pill can read them too.
enum FoodSettings {
    static let dailyCaloriesKey = "food.dailyCalories"
    static let weeklyBudgetKey = "food.weeklyBudget"
    static let weeklyCheatsKey = "food.weeklyCheatAllowance"
    static let cheatEarlyKey = "food.cheatEarly"
    static let earlyMinutesKey = "food.earlyMinutes"
    static let cheatLatePlanKey = "food.cheatLatePlan"
    static let showPillKey = "food.showPill"
    static let notifyKey = "food.notify"
    static let planReminderKey = "food.planReminderMinutes"
    static let urgeMinutesKey = "food.urgeMinutes"
    static let acknowledgeKey = "food.acknowledge"
    static let lastSnoozeKey = "food.lastSnoozeMinutes"
    static let pillXKey = "food.pillX"
    static let pillYKey = "food.pillY"

    private static var d: UserDefaults { .standard }
    private static func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: key) as? Int ?? fallback }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) as? Bool ?? fallback }

    static var dailyCalories: Int { int(dailyCaloriesKey, 2000) }
    static var weeklyBudget: Double { d.object(forKey: weeklyBudgetKey) as? Double ?? 0 }
    static var weeklyCheatAllowance: Int { int(weeklyCheatsKey, 2) }
    static var cheatEarly: Bool { bool(cheatEarlyKey, false) }
    static var earlyMinutes: Int { int(earlyMinutesKey, 30) }
    static var cheatLatePlan: Bool { bool(cheatLatePlanKey, false) }
    static var showPill: Bool { bool(showPillKey, true) }
    static var notify: Bool { bool(notifyKey, true) }
    static var planReminderMinutes: Int { int(planReminderKey, 21 * 60) }
    static var urgeMinutes: Int { int(urgeMinutesKey, 10) }
    static var acknowledge: Bool { bool(acknowledgeKey, true) }

    static let triggers = ["Hungry", "Stressed", "Bored", "Social", "Tired", "Saw it", "Habit", "Sad"]

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0...2)))
    }
}

// MARK: - Rules

/// A row in a day's schedule: a saved planned entry, or a template break
/// that hasn't been planned yet for that day.
struct FoodSlot: Identifiable {
    let id: UUID
    /// When it's due, after any snooze.
    let time: Date
    /// The planned time, before any snooze.
    let plannedTime: Date
    let name: String
    let icon: String
    let entry: FoodEntry?

    var food: String { entry?.food ?? "" }
    var status: FoodEntryStatus { entry?.status ?? .pending }
    var isSnoozed: Bool { time != plannedTime }
}

enum FoodCheatReason: String {
    case unplanned = "Unplanned food"
    case swapped = "Ate something else"
    case early = "Ate too early"
    case latePlan = "Planned on the day"
}

enum FoodRules {
    static func entries(on day: Date, _ all: [FoodEntry]) -> [FoodEntry] {
        let d = day.startOfDay
        return all.filter { $0.day == d }.sorted { $0.time < $1.time }
    }

    static func templateBreaks(for date: Date, _ breaks: [FoodBreak]) -> [FoodBreak] {
        breaks.filter { $0.applies(to: date) }.sorted { $0.minutes < $1.minutes }
    }

    /// The day's planned breaks; template breaks if the day has no plan yet.
    static func slots(on day: Date, entries all: [FoodEntry], breaks: [FoodBreak]) -> [FoodSlot] {
        let planned = entries(on: day, all).filter { $0.kind == .planned }
        if !planned.isEmpty {
            return planned
                .map { FoodSlot(id: $0.id, time: $0.effectiveTime, plannedTime: $0.time, name: $0.breakName, icon: $0.icon, entry: $0) }
                .sorted { $0.time < $1.time }
        }
        return templateBreaks(for: day, breaks).map {
            FoodSlot(id: $0.id, time: $0.time(on: day), plannedTime: $0.time(on: day), name: $0.name, icon: $0.icon, entry: nil)
        }
    }

    /// Every planned break has food written down.
    static func isDayPlanned(_ day: Date, entries all: [FoodEntry]) -> Bool {
        let planned = entries(on: day, all).filter { $0.kind == .planned }
        return !planned.isEmpty && planned.allSatisfy(\.hasPlan)
    }

    static func plannedCount(_ day: Date, entries all: [FoodEntry]) -> (planned: Int, total: Int) {
        let planned = entries(on: day, all).filter { $0.kind == .planned }
        return (planned.filter(\.hasPlan).count, planned.count)
    }

    /// Why an entry counts as a cheat, or nil if it doesn't.
    static func cheatReason(_ e: FoodEntry) -> FoodCheatReason? {
        if e.isUnplanned { return e.wasConsumed ? .unplanned : nil }
        if e.status == .swapped { return .swapped }
        guard e.status == .eaten else { return nil }
        if FoodSettings.cheatEarly, let eatenAt = e.eatenAt,
           eatenAt < e.time.addingTimeInterval(-Double(FoodSettings.earlyMinutes) * 60) {
            return .early
        }
        if FoodSettings.cheatLatePlan, !e.plannedOnTime { return .latePlan }
        return nil
    }

    static func cheats(_ entries: [FoodEntry]) -> [FoodEntry] {
        entries.filter { cheatReason($0) != nil }
    }

    /// The next break still to come (today, or the first one tomorrow).
    static func nextSlot(after now: Date, entries all: [FoodEntry], breaks: [FoodBreak]) -> FoodSlot? {
        for offset in 0...1 {
            let day = Calendar.current.date(byAdding: .day, value: offset, to: now.startOfDay)!
            if let slot = slots(on: day, entries: all, breaks: breaks)
                .first(where: { $0.time > now && $0.status == .pending }) {
                return slot
            }
        }
        return nil
    }

    /// A break that has started (within the last 2 hours) and isn't marked yet.
    static func dueSlot(at now: Date, entries all: [FoodEntry], breaks: [FoodBreak]) -> FoodSlot? {
        slots(on: now, entries: all, breaks: breaks)
            .last { $0.time <= now && now.timeIntervalSince($0.time) < 2 * 3600 && $0.status == .pending }
    }

    private static let trackingStartKey = "food.trackingStart"

    /// The day food tracking began. Days before it (e.g. meals copied from the
    /// old Day Plan) had no way to log unplanned food, so they're never "clean".
    static func trackingStart(breaks: [FoodBreak]) -> Date {
        let stored = UserDefaults.standard.double(forKey: trackingStartKey)
        if stored > 0 { return Date(timeIntervalSince1970: stored) }
        let start = (breaks.map(\.createdAt).min() ?? Date()).startOfDay
        UserDefaults.standard.set(start.timeIntervalSince1970, forKey: trackingStartKey)
        return start
    }

    /// Tracked, at least one food marked as eaten, and no cheats.
    static func isCleanDay(_ day: Date, entries all: [FoodEntry], since start: Date) -> Bool {
        guard day.startOfDay >= start else { return false }
        let list = entries(on: day, all)
        return list.contains(where: \.wasConsumed) && cheats(list).isEmpty
    }

    /// Clean days in a row, ending yesterday (or today, once today has food marked).
    static func cleanStreak(entries all: [FoodEntry], breaks: [FoodBreak], now: Date = Date()) -> Int {
        let start = trackingStart(breaks: breaks)
        let cal = Calendar.current
        var day = now.startOfDay
        if !isCleanDay(day, entries: all, since: start) {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while isCleanDay(day, entries: all, since: start) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    static func weekStart(_ date: Date) -> Date { GoalPeriod.week.start(for: date) }

    static func entries(_ all: [FoodEntry], from start: Date, to end: Date) -> [FoodEntry] {
        all.filter { $0.day >= start && $0.day < end }
    }

    /// Creates a day's planned entries from the template (empty food), so the
    /// day can be marked as eaten/skipped before it was planned.
    @discardableResult
    static func materialize(_ day: Date, breaks: [FoodBreak], context: ModelContext) -> [FoodEntry] {
        let all = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let existing = entries(on: day, all).filter { $0.kind == .planned }
        if !existing.isEmpty { return existing }
        let created = templateBreaks(for: day, breaks).map {
            FoodEntry(day: day, time: $0.time(on: day), kind: .planned, breakID: $0.id, breakName: $0.name, icon: $0.icon)
        }
        created.forEach { context.insert($0) }
        return created
    }

    /// Marks a slot, creating the day's entries first if needed.
    static func mark(_ slot: FoodSlot, _ status: FoodEntryStatus, day: Date, breaks: [FoodBreak], context: ModelContext) {
        let entry = slot.entry ?? materialize(day, breaks: breaks, context: context)
            .first { $0.breakID == slot.id || ($0.breakName == slot.name && $0.time == slot.time) }
        guard let entry else { return }
        acknowledge(slot)
        entry.status = status
        entry.eatenAt = status == .pending || status == .skipped ? nil : Date()
        if status != .swapped {
            entry.actualFood = ""; entry.actualCalories = nil; entry.actualCost = nil
        }
        try? context.save()
        FoodNotifications.reschedule(context: context)
    }
}

// MARK: - Snooze & acknowledgment

extension FoodRules {
    /// Delays a break by `minutes`: from its time if it's still ahead,
    /// otherwise from now. Can be done again to add more.
    static func snooze(_ slot: FoodSlot, minutes: Int, day: Date, breaks: [FoodBreak],
                       context: ModelContext, now: Date = Date()) {
        let entry = slot.entry ?? materialize(day, breaks: breaks, context: context)
            .first { $0.breakID == slot.id || ($0.breakName == slot.name && $0.time == slot.plannedTime) }
        guard let entry else { return }
        acknowledge(slot)
        let base = max(slot.time, now)
        entry.snoozedUntil = base.addingTimeInterval(Double(max(1, minutes)) * 60)
        entry.snoozeCount += 1
        try? context.save()
        FoodNotifications.reschedule(context: context)
    }

    /// Same id before and after a day's plan is saved, so acknowledging a
    /// template break carries over. A snooze gives it a new time, so it asks again.
    private static func ackID(_ slot: FoodSlot) -> String {
        "food-\(slot.name)@\(Int(slot.time.timeIntervalSince1970 / 60))"
    }

    /// The break that has started and wants acknowledging, if any.
    static func needingAcknowledgment(at now: Date, entries: [FoodEntry], breaks: [FoodBreak]) -> FoodSlot? {
        guard FoodSettings.acknowledge,
              let slot = dueSlot(at: now, entries: entries, breaks: breaks) else { return nil }
        return AcknowledgmentStore.isAcknowledged(date: slot.time, identifier: ackID(slot)) ? nil : slot
    }

    static func acknowledge(_ slot: FoodSlot) {
        AcknowledgmentStore.acknowledge(date: slot.time, identifier: ackID(slot))
    }
}

// MARK: - Craving wait timer

/// One shared timer, so the pill and the Food screen show the same wait.
enum FoodUrge {
    static let startedAtKey = "food.urge.startedAt"
    static let triggerKey = "food.urge.trigger"

    enum State { case idle, waiting(Int), done }

    static func state(at now: Date = Date()) -> State {
        let started = UserDefaults.standard.double(forKey: startedAtKey)
        guard started > 0 else { return .idle }
        let end = started + Double(FoodSettings.urgeMinutes) * 60
        let left = Int(end - now.timeIntervalSince1970)
        return left > 0 ? .waiting(left) : .done
    }

    static var trigger: String { UserDefaults.standard.string(forKey: triggerKey) ?? "" }

    static func start(trigger: String = "") {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: startedAtKey)
        UserDefaults.standard.set(trigger, forKey: triggerKey)
        guard FoodSettings.notify else { return }
        let content = UNMutableNotificationContent()
        content.title = "Craving check"
        content.body = "\(FoodSettings.urgeMinutes) minutes are up. Do you still want it?"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "food-urge", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(FoodSettings.urgeMinutes) * 60, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    /// Ends the wait and records how it went.
    static func finish(resisted: Bool, context: ModelContext) {
        let started = UserDefaults.standard.double(forKey: startedAtKey)
        if started > 0 {
            let waited = Int(Date().timeIntervalSince1970 - started)
            context.insert(FoodCraving(date: Date(), trigger: trigger, resisted: resisted, waitedSeconds: waited))
            try? context.save()
        }
        cancel()
    }

    static func cancel() {
        UserDefaults.standard.set(0.0, forKey: startedAtKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["food-urge"])
    }
}

// MARK: - Notifications

enum FoodNotifications {
    /// Alerts for today's and tomorrow's remaining breaks, plus an evening
    /// reminder if tomorrow isn't planned yet.
    static func reschedule(context: ModelContext) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix("food-break-") || $0 == "food-plan-reminder" }
            center.removePendingNotificationRequests(withIdentifiers: old)
        }
        guard FoodSettings.notify else { return }

        let entries = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let breaks = (try? context.fetch(FetchDescriptor<FoodBreak>())) ?? []
        let now = Date()
        let cal = Calendar.current

        for offset in 0...1 {
            let day = cal.date(byAdding: .day, value: offset, to: now.startOfDay)!
            for slot in FoodRules.slots(on: day, entries: entries, breaks: breaks)
            where slot.time > now && slot.status == .pending {
                let content = UNMutableNotificationContent()
                content.title = "\(slot.name) time"
                let food = slot.food.isEmpty ? "Nothing planned for this break." : slot.food
                content.body = FoodSettings.acknowledge ? "\(food)\nOpen the app to acknowledge." : food
                content.sound = .default
                content.interruptionLevel = .timeSensitive
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: slot.time)
                center.add(UNNotificationRequest(identifier: "food-break-\(slot.id.uuidString)", content: content,
                                                 trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
            }
        }

        let tomorrow = cal.date(byAdding: .day, value: 1, to: now.startOfDay)!
        let reminder = cal.date(byAdding: .minute, value: FoodSettings.planReminderMinutes, to: now.startOfDay)!
        if reminder > now && !FoodRules.isDayPlanned(tomorrow, entries: entries) {
            let content = UNMutableNotificationContent()
            content.title = "Plan tomorrow's food"
            content.body = "Write down what you'll eat at each break, so tomorrow's food counts as planned."
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: reminder)
            center.add(UNNotificationRequest(identifier: "food-plan-reminder", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - Setup

enum FoodSetup {
    private static let key = "food.setup.v1"

    /// Adds the default breaks, and copies old Day Plan meals
    /// (breakfast/lunch/dinner) into food entries. Runs once.
    static func runOnce(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        if ((try? context.fetchCount(FetchDescriptor<FoodBreak>())) ?? 0) == 0 {
            let defaults: [(String, String, Int)] = [
                ("Breakfast", "sun.horizon.fill", 7 * 60),
                ("Coffee", "cup.and.saucer.fill", 10 * 60),
                ("Lunch", "fork.knife", 12 * 60),
                ("Coffee", "cup.and.saucer.fill", 15 * 60),
                ("Dinner", "moon.stars.fill", 20 * 60)
            ]
            for (name, icon, minutes) in defaults {
                context.insert(FoodBreak(name: name, icon: icon, minutes: minutes))
            }
        }

        let days = (try? context.fetch(FetchDescriptor<PlannerDay>())) ?? []
        for p in days where p.mealsPlanned > 0 {
            let meals: [(String, String, String, Date?, Bool, Int)] = [
                ("Breakfast", "sun.horizon.fill", p.breakfast, p.breakfastTime, p.breakfastEaten, 8),
                ("Lunch", "fork.knife", p.lunch, p.lunchTime, p.lunchEaten, 13),
                ("Dinner", "moon.stars.fill", p.dinner, p.dinnerTime, p.dinnerEaten, 19)
            ]
            for (name, icon, food, time, eaten, hour) in meals {
                let at = time ?? Calendar.current.date(byAdding: .hour, value: hour, to: p.date)!
                let entry = FoodEntry(day: p.date, time: at, kind: .planned, breakName: name, icon: icon,
                                      food: food.trimmingCharacters(in: .whitespaces))
                entry.plannedAt = entry.hasPlan ? p.createdAt : nil
                if eaten { entry.status = .eaten; entry.eatenAt = at }
                context.insert(entry)
            }
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
