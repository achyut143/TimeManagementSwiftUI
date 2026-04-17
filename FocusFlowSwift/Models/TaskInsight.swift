import Foundation
import SwiftData

/// Cached AI insights for a specific task + date range.
/// One record per (taskTitle, fromDate, toDate) combination.
@Model
class TaskInsight {
    var taskTitle: String   // lowercase-trimmed key, or "all" for all repeat tasks
    var fromDate: Date
    var toDate: Date
    var insightCount: Int
    var insightsRaw: String // newline-separated insight strings
    var generatedAt: Date

    init(taskTitle: String, fromDate: Date, toDate: Date, insightCount: Int, insights: [String]) {
        self.taskTitle    = taskTitle.lowercased().trimmingCharacters(in: .whitespaces)
        self.fromDate     = Calendar.current.startOfDay(for: fromDate)
        self.toDate       = Calendar.current.startOfDay(for: toDate)
        self.insightCount = insightCount
        self.insightsRaw  = insights.joined(separator: "\n")
        self.generatedAt  = Date()
    }

    var insights: [String] {
        insightsRaw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func matches(taskTitle: String, fromDate: Date, toDate: Date) -> Bool {
        let cal = Calendar.current
        return self.taskTitle == taskTitle.lowercased().trimmingCharacters(in: .whitespaces)
            && cal.isDate(self.fromDate, inSameDayAs: fromDate)
            && cal.isDate(self.toDate, inSameDayAs: toDate)
    }

    func update(insights: [String], insightCount: Int) {
        self.insightsRaw  = insights.joined(separator: "\n")
        self.insightCount = insightCount
        self.generatedAt  = Date()
    }
}
