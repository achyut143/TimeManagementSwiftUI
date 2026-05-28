import SwiftData
import Foundation

@Model
class Goal {
    var id: UUID = UUID()
    var name: String
    var goalDescription: String

    @Relationship(deleteRule: .nullify, inverse: \Task.goal)
    var tasks: [Task]? = []

    init(name: String, goalDescription: String = "") {
        self.id = UUID()
        self.name = name
        self.goalDescription = goalDescription
    }

    var taskCount: Int { tasks?.count ?? 0 }

    var completedTaskCount: Int { tasks?.filter { $0.completed }.count ?? 0 }

    var completionPercentage: Double {
        let total = taskCount
        guard total > 0 else { return 0.0 }
        return Double(completedTaskCount) / Double(total) * 100.0
    }
}
