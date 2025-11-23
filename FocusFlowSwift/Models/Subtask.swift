import SwiftData
import Foundation

@Model
class Subtask {
    var name: String
    var notes: String?
    var parentTask: Task? // Direct relationship to parent task
    var parentSubtask: Subtask? // For nested subtasks
    var completed: Bool
    var createdAt: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Subtask.parentSubtask)
    var childSubtasks: [Subtask]? = []
    
    init(name: String = "", notes: String? = nil, parentTask: Task? = nil, parentSubtask: Subtask? = nil, completed: Bool = false) {
        self.name = name
        self.notes = notes
        self.parentTask = parentTask
        self.parentSubtask = parentSubtask
        self.completed = completed
        self.createdAt = Date()
    }
}
