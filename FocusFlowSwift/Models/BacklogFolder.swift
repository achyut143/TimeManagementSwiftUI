import SwiftData
import Foundation

// A user-created bucket for organizing backlog tasks — tasks that exist but
// haven't been scheduled onto a specific day yet (Task.date == nil). Folders
// are flat (no nesting) to keep the backlog picker simple. Tasks with no
// folder ("Unfiled") aren't a stored folder — they're just backlog tasks
// whose backlogFolder is nil.
@Model
class BacklogFolder {
    var id: UUID = UUID()
    var name: String
    // User-arranged display order (lower sorts first).
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    // .nullify (not .cascade): deleting a folder un-files its tasks back to
    // "Unfiled" rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \Task.backlogFolder)
    var tasks: [Task]? = []

    init(name: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}
