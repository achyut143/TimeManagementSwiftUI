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
    /// Position among its siblings (lower comes first). Added later: older
    /// subtasks are all 0, so they fall back to creation order.
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Subtask.parentSubtask)
    var childSubtasks: [Subtask]? = []

    init(name: String = "", notes: String? = nil, parentTask: Task? = nil, parentSubtask: Subtask? = nil, completed: Bool = false, sortOrder: Int = 0) {
        self.name = name
        self.notes = notes
        self.parentTask = parentTask
        self.parentSubtask = parentSubtask
        self.completed = completed
        self.createdAt = Date()
        self.sortOrder = sortOrder
    }
}

/// Keeps subtasks in the user's order: sorting, adding, reordering and copying.
enum SubtaskOrder {
    /// By position, then by creation time (so old subtasks keep their old order).
    static func sorted(_ subtasks: [Subtask]) -> [Subtask] {
        subtasks.sorted {
            $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.createdAt < $1.createdAt
        }
    }

    /// Top-level subtasks of a task, in order.
    static func topLevel(of task: Task) -> [Subtask] {
        sorted((task.subtasks ?? []).filter { $0.parentSubtask == nil })
    }

    /// Position for a new subtask: after the last sibling.
    static func nextOrder(after siblings: [Subtask]) -> Int {
        (siblings.map(\.sortOrder).max() ?? -1) + 1
    }

    /// Writes 0, 1, 2… in the given order.
    static func renumber(_ ordered: [Subtask]) {
        for (index, subtask) in ordered.enumerated() where subtask.sortOrder != index {
            subtask.sortOrder = index
        }
    }

    /// Applies a List drag (`onMove`) to siblings shown in `ordered`.
    static func move(_ ordered: [Subtask], from source: IndexSet, to destination: Int) {
        var items = ordered
        items.move(fromOffsets: source, toOffset: destination)
        renumber(items)
    }

    /// Moves one subtask by `step` places (-1 = up, +1 = down), stopping at the ends.
    static func shift(_ subtask: Subtask, by step: Int, in ordered: [Subtask]) {
        var items = ordered
        guard step != 0,
              let from = items.firstIndex(where: { $0.persistentModelID == subtask.persistentModelID })
        else { return }
        let to = min(max(from + step, 0), items.count - 1)
        items.remove(at: from)
        items.insert(subtask, at: to)
        renumber(items)
    }

    /// Copies all of `source`'s subtasks (and nested ones) onto `target`,
    /// unchecked, in the same order.
    static func copyAll(from source: Task, to target: Task, context: ModelContext) {
        for (index, subtask) in topLevel(of: source).enumerated() {
            copy(subtask, order: index, to: target, parent: nil, context: context)
        }
    }

    private static func copy(_ subtask: Subtask, order: Int, to task: Task, parent: Subtask?, context: ModelContext) {
        let copy = Subtask(
            name: subtask.name,
            notes: subtask.notes,
            parentTask: task,
            parentSubtask: parent,
            completed: false,
            sortOrder: order
        )
        context.insert(copy)
        for (index, child) in sorted(subtask.childSubtasks ?? []).enumerated() {
            Self.copy(child, order: index, to: task, parent: copy, context: context)
        }
    }
}
