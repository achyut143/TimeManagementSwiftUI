import Foundation
import SwiftData

/// Ending and resuming habits (repeat series), and reading when one ended.
///
/// A habit's end is the end date on its most recent task (`repeatEndDate`).
/// It counts as ended once that day has passed.
@MainActor
enum HabitEnd {
    /// Tasks of a habit, by its habit name.
    static func members(of habitName: String, in tasks: [Task]) -> [Task] {
        tasks.filter { $0.repeatSeriesID != nil && $0.habitName == habitName }
    }

    /// The most recent task's end date, if it has one.
    static func endDate(of habitName: String, in tasks: [Task]) -> Date? {
        let latest = members(of: habitName, in: tasks).max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return latest?.repeatEndDate
    }

    /// End date that has passed (habit is over); nil if active or ending later.
    static func endedDate(of habitName: String, in tasks: [Task]) -> Date? {
        guard let end = endDate(of: habitName, in: tasks) else { return nil }
        return Calendar.current.startOfDay(for: end) < Calendar.current.startOfDay(for: Date()) ? end : nil
    }

    /// Every ended habit with its end date.
    static func endedHabits(in tasks: [Task]) -> [String: Date] {
        let names = Set(tasks.filter { $0.repeatSeriesID != nil && $0.repeatAgain != nil }.map(\.habitName))
        var result: [String: Date] = [:]
        for name in names {
            if let d = endedDate(of: name, in: tasks) { result[name] = d }
        }
        return result
    }

    /// First day of the habit (for the end-date picker).
    static func startDate(of habitName: String, in tasks: [Task]) -> Date? {
        members(of: habitName, in: tasks).compactMap(\.date).min()
    }

    /// Ends the habit on `day` (its last day). Pending copies after that day
    /// are removed; done or not-done ones stay as history.
    static func end(_ habitName: String, on day: Date, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        let cal = Calendar.current
        let last = cal.startOfDay(for: day)
        for t in members(of: habitName, in: all) {
            let d = cal.startOfDay(for: t.date ?? last)
            if d > last {
                if !t.completed && !t.notCompleted { context.delete(t) }
            } else if t.repeatAgain != nil {
                t.repeatEndDate = last
            }
        }
        try? context.save()
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
    }

    /// Clears the end date so it repeats again; today's copy is added right away.
    static func resume(_ habitName: String, context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        for t in members(of: habitName, in: all) { t.repeatEndDate = nil }
        try? context.save()
        RepeatScheduler.fillToday(context: context)
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
    }

    /// Done vs missed over the habit's whole life, one entry per day.
    static func lifetimeCounts(of habitName: String, in tasks: [Task]) -> (completed: Int, missed: Int) {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: members(of: habitName, in: tasks).filter { $0.date != nil }) {
            cal.startOfDay(for: $0.date!)
        }
        var done = 0, missed = 0
        for (_, dayTasks) in byDay {
            if dayTasks.contains(where: \.completed) { done += 1 }
            else if dayTasks.contains(where: \.notCompleted) { missed += 1 }
        }
        return (done, missed)
    }
}
