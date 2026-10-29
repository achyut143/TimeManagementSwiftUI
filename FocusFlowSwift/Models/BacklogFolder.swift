import SwiftData
import Foundation

// A user-created bucket for organizing backlog tasks — tasks that exist but
// haven't been scheduled onto a specific day yet (Task.date == nil). Folders
// can sit inside other folders (parentID). Tasks with no folder ("Unfiled")
// aren't a stored folder — they're just backlog tasks whose backlogFolder is nil.
@Model
class BacklogFolder {
    var id: UUID = UUID()
    var name: String
    // User-arranged display order (lower sorts first).
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    /// The folder it's inside; nil = top level. (Added later; older folders are top level.)
    var parentID: UUID? = nil

    // .nullify (not .cascade): deleting a folder un-files its tasks back to
    // "Unfiled" rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \Task.backlogFolder)
    var tasks: [Task]? = []

    init(name: String, sortOrder: Int = 0, parentID: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.parentID = parentID
        self.createdAt = Date()
    }
}
