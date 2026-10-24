import Foundation
import SwiftData

/// Creates the next occurrence of a repeat task (`repeatAgain` days later,
/// same start/end time). Shared by task completion and snoozing.
///
/// About `Task.reassign` — the green/red repeat icon on a task row:
/// green (false) = completing / not-completing this task creates its next
/// occurrence; red (true) = it won't, because the next one is already handled
/// (a rolled-over copy, a snoozed task, or turned off by tapping the icon).
enum TaskRepeater {
    static func createNextInstance(from task: Task, context: ModelContext) {
        guard let repeatDays = task.repeatAgain, let currentDate = task.date else { return }

        let nextDate = Calendar.current.date(byAdding: .day, value: repeatDays, to: currentDate) ?? currentDate

        // Skip if that occurrence already exists.
        let existing = (try? context.fetch(FetchDescriptor<Task>())) ?? []
        let exists = existing.contains { other in
            guard let d = other.date else { return false }
            return Calendar.current.isDate(d, inSameDayAs: nextDate) &&
                other.startTime == task.startTime &&
                other.endTime == task.endTime &&
                other.title == task.title
        }
        if exists { return }

        let newTask = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: task.startTime,
            endTime: task.endTime,
            weight: task.weight,
            date: nextDate,
            repeatAgain: task.repeatAgain,
            priority: task.priority,
            elapsedTime: task.elapsedTime,
            copySubtasks: task.copySubtasks,
            whyStatement: task.whyStatement,
            whyStatementPinned: task.whyStatementPinned,
            virtues: task.virtues
            // timeSpent is intentionally not copied for repeat tasks
        )
        newTask.goal = task.goal
        ImpulseRules.inherit(from: task, to: newTask, context: context)
        context.insert(newTask)

        if task.copySubtasks, let subtasks = task.subtasks?.filter({ $0.parentSubtask == nil }) {
            for subtask in subtasks {
                copySubtask(subtask, to: newTask, parent: nil, context: context)
            }
        }

        try? context.save()
    }

    private static func copySubtask(_ subtask: Subtask, to task: Task, parent: Subtask?, context: ModelContext) {
        let copy = Subtask(
            name: subtask.name,
            notes: subtask.notes,
            parentTask: task,
            parentSubtask: parent,
            completed: false
        )
        context.insert(copy)
        for child in subtask.childSubtasks ?? [] {
            copySubtask(child, to: task, parent: copy, context: context)
        }
    }
}

/// Moving timed tasks within a day. Used by Snooze, Move Tasks, dragging a
/// task on the timeline, and changing a task's start time in Edit Task.
///
/// Rules:
/// - Followers: any task starting within `followWindowMinutes` after a moved
///   task ends moves by the same amount — and so on down the chain.
///   Completed / not-completed tasks stay put.
/// - Repeat tasks get their next occurrence created first, at the original
///   time, and are marked red (`reassign = true`) so completing the moved
///   task doesn't create another one at the new time.
enum TaskMover {
    static let followWindowMinutes = 10

    /// Tasks on the same day that follow `moving` closely (see type docs),
    /// in start-time order. Doesn't include `moving` itself. Call this
    /// before changing any times.
    static func followers(of moving: [Task], context: ModelContext) -> [Task] {
        let timed = moving.filter { $0.date != nil && minutes($0.startTime) != nil && minutes($0.endTime) != nil }
        guard let day = timed.first?.date else { return [] }
        let movingIDs = Set(moving.map(\.id))

        let candidates = ((try? context.fetch(FetchDescriptor<Task>())) ?? []).filter { other in
            guard !movingIDs.contains(other.id),
                  let d = other.date, Calendar.current.isDate(d, inSameDayAs: day),
                  !other.completed, !other.notCompleted,
                  minutes(other.startTime) != nil, minutes(other.endTime) != nil else { return false }
            return true
        }
        .sorted { (minutes($0.startTime) ?? 0) < (minutes($1.startTime) ?? 0) }

        // (start, end) of everything moving so far, in original times.
        var spans: [(Int, Int)] = timed
            .filter { Calendar.current.isDate($0.date!, inSameDayAs: day) }
            .map { span($0) }
        var result: [Task] = []
        for c in candidates {
            let (cs, ce) = span(c)
            let follows = spans.contains { s, e in cs >= s && cs - e <= followWindowMinutes }
            if follows {
                result.append(c)
                spans.append((cs, ce))
            }
        }
        return result
    }

    /// The task itself plus its followers.
    static func tasksToMove(for task: Task, context: ModelContext) -> [Task] {
        [task] + followers(of: [task], context: context)
    }

    /// Creates repeat tasks' next occurrence at their current (original)
    /// time and marks them red. Call before changing times.
    static func prepareRepeats(_ tasks: [Task], context: ModelContext) {
        for t in tasks where t.repeatAgain != nil && !t.reassign {
            TaskRepeater.createNextInstance(from: t, context: context)
            t.reassign = true
        }
    }

    /// Shifts start/end of each task by `delta` minutes (no followers, no
    /// repeat handling — callers do those first).
    static func shift(_ tasks: [Task], by delta: Int, impulseTypes: [ImpulseType]) {
        for t in tasks {
            guard let s = minutes(t.startTime), let e = minutes(t.endTime) else { continue }
            let before = ImpulseRules.Snapshot(t)
            t.startTime = format(s + delta)
            t.endTime = format(e + delta)
            ImpulseRules.reconcile(t, before: before, types: impulseTypes)
        }
    }

    /// Moves `tasks` and their followers by `delta` minutes, handling
    /// repeats. Returns everything that moved.
    @discardableResult
    static func move(_ tasks: [Task], by delta: Int, context: ModelContext, impulseTypes: [ImpulseType]) -> [Task] {
        guard delta != 0, !tasks.isEmpty else { return [] }
        let all = tasks + followers(of: tasks, context: context)
        prepareRepeats(all, context: context)
        shift(all, by: delta, impulseTypes: impulseTypes)
        try? context.save()
        return all
    }

    /// Snooze = move one task (and its followers) later.
    @discardableResult
    static func snooze(_ task: Task, by delta: Int, context: ModelContext, impulseTypes: [ImpulseType]) -> [Task] {
        move([task], by: delta, context: context, impulseTypes: impulseTypes)
    }

    /// Start/end in minutes, with an end past midnight counted as next day.
    private static func span(_ t: Task) -> (Int, Int) {
        let s = minutes(t.startTime) ?? 0
        let e = minutes(t.endTime) ?? s
        return (s, e < s ? e + 24 * 60 : e)
    }

    static func minutes(_ time: String) -> Int? {
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    static func format(_ minutes: Int) -> String {
        var m = minutes % (24 * 60)
        if m < 0 { m += 24 * 60 }
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
