import Foundation
import SwiftData

// MARK: - Dates

enum PlanDates {
    // Weeks run Mon–Sun, matching the weekly template.
    static func weekStart(for date: Date) -> Date {
        let day = date.startOfDay
        let weekday = Calendar.current.component(.weekday, from: day) // 1 = Sun
        return Calendar.current.date(byAdding: .day, value: -((weekday + 5) % 7), to: day)!
    }

    static func quarterStart(for date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let firstMonth = ((comps.month! - 1) / 3) * 3 + 1
        return Calendar.current.date(from: DateComponents(year: comps.year, month: firstMonth, day: 1))!
    }

    static func quarterLabel(for date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "Q\((comps.month! - 1) / 3 + 1) \(comps.year!)"
    }

    static func adding(_ days: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date.startOfDay)!
    }
}

// MARK: - If-then

@Model
final class IfThenPlan {
    var trigger: String = ""
    var response: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(trigger: String = "", response: String = "", sortOrder: Int = 0) {
        self.trigger = trigger
        self.response = response
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    /// Inserts the starter examples the first time if-then plans are used.
    /// Same "plan.ifThenSeeded" flag the old Plan view used, so deleting
    /// every plan doesn't bring the examples back.
    static func seedIfNeeded(context: ModelContext) {
        let key = "plan.ifThenSeeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard ((try? context.fetchCount(FetchDescriptor<IfThenPlan>())) ?? 0) == 0 else { return }
        for (index, pair) in defaults.enumerated() {
            context.insert(IfThenPlan(trigger: pair.0, response: pair.1, sortOrder: index))
        }
        try? context.save()
    }

    static let defaults: [(String, String)] = [
        ("I feel too tired for the gym", "Do just 10 minutes, then decide"),
        ("Friends order another round", "Switch to soda or water"),
        ("I want one more episode", "Stop, make tea, read 10 pages"),
        ("I slip up", "Forgive myself and restart at the next choice, not Monday")
    ]
}
