import SwiftData
import Foundation

@Model
class Subtask {
    var name: String
    var notes: String?
    var parentTaskIdString: String? // Store persistentModelID as string
    var parentSubtaskIdString: String? // For nested subtasks
    var completed: Bool
    var createdAt: Date
    
    init(name: String = "", notes: String? = nil, parentTaskIdString: String? = nil, parentSubtaskIdString: String? = nil, completed: Bool = false) {
        self.name = name
        self.notes = notes
        self.parentTaskIdString = parentTaskIdString
        self.parentSubtaskIdString = parentSubtaskIdString
        self.completed = completed
        self.createdAt = Date()
    }
    
    // Convenience initializers for creating from Task/Subtask
    convenience init(name: String = "", notes: String? = nil, parentTask: Task? = nil, parentSubtask: Subtask? = nil, completed: Bool = false) {
        self.init(
            name: name,
            notes: notes,
            parentTaskIdString: parentTask?.persistentModelID.hashValue.description,
            parentSubtaskIdString: parentSubtask?.persistentModelID.hashValue.description,
            completed: completed
        )
    }
}
