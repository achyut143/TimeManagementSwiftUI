import Foundation
import SwiftData

/// One OKR record per unique repeat-task title.
/// `taskTitle` is stored lowercase-trimmed so it works as a stable key across task instances.
@Model
class TaskOKR {
    var taskTitle: String       // lowercase-trimmed key
    var displayTitle: String    // original casing for display
    var repeatInterval: Int     // repeatAgain value (days between repeats)
    var objective: String
    var keyResults: String
    var createdAt: Date
    var updatedAt: Date

    init(taskTitle: String, displayTitle: String, repeatInterval: Int,
         objective: String = "", keyResults: String = "") {
        self.taskTitle      = taskTitle.lowercased().trimmingCharacters(in: .whitespaces)
        self.displayTitle   = displayTitle
        self.repeatInterval = repeatInterval
        self.objective      = objective
        self.keyResults     = keyResults
        self.createdAt      = Date()
        self.updatedAt      = Date()
    }

    func update(objective: String, keyResults: String) {
        self.objective  = objective
        self.keyResults = keyResults
        self.updatedAt  = Date()
    }
}
