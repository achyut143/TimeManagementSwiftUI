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
            whyStatementPinned: task.whyStatementPinned
            // timeSpent is intentionally not copied for repeat tasks
        )
        newTask.goal = task.goal
        ImpulseRules.inherit(from: task, to: newTask, context: context)
        context.insert(newTask)

        if task.copySubtasks {
            SubtaskOrder.copyAll(from: task, to: newTask, context: context)
        }

        try? context.save()
    }

}

/// Moving timed tasks within a day. Used by Snooze, Extend and Move Tasks.
///
/// Rules, applied down the chain in start-time order:
/// - Followers: a task starting 0–`followWindowMinutes` after a moving task's
///   original end moves by that task's full amount (tight blocks stay together).
/// - Overlaps: the moved tasks keep the time chosen. Any other pending task
///   they now overlap — whether it starts after them, they land in the middle
///   of it, or they were moved earlier onto it — is pushed to start when the
///   moved task ends. Tasks that already overlapped before the move are left
///   as they were.
///   e.g. A 12:30–1:00, B 1:00–1:30, C 1:50–2:30; move A +30 →
///   A 1:00–1:30, B 1:30–2:00 (follower), C 2:00–2:40 (pushed 10).
///   e.g. A 9:00–9:30, X 11:00–12:00; move A to 11:15 → X 11:45–12:45.
/// - Completed / not-completed tasks stay put.
/// - Repeat tasks get their next occurrence created first, at the original
///   time, and are marked red (`reassign = true`) so completing the moved
///   task doesn't create another one at the new time.
enum TaskMover {
    static let followWindowMinutes = 10

    /// A task that gets pushed along, and by how many minutes.
    struct Push {
        let task: Task
        let delta: Int
        var newStartTime: String { format((minutes(task.startTime) ?? 0) + delta) }
        var newEndTime: String { format((minutes(task.endTime) ?? 0) + delta) }
    }

    /// Other tasks on the same day that get pushed when `moving` changes by
    /// `startDelta` / `endDelta` minutes (see type docs), in start-time order.
    /// Doesn't include `moving` itself. Call before changing any times.
    static func pushes(for moving: [Task], startDelta: Int, endDelta: Int, context: ModelContext) -> [Push] {
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

        // Everything moving so far: original and new spans, and how far its end moves.
        struct Planned { let s, e, ns, ne, endDelta: Int }
        var planned: [Planned] = timed
            .filter { Calendar.current.isDate($0.date!, inSameDayAs: day) }
            .map { t in
                let (s, e) = span(t)
                return Planned(s: s, e: e, ns: s + startDelta, ne: e + endDelta, endDelta: endDelta)
            }

        var result: [Push] = []
        for c in candidates {
            let (cs, ce) = span(c)

            // Follower: starts within the window after a moving task's original end.
            let followDeltas = planned
                .filter { cs >= $0.s && cs - $0.e <= followWindowMinutes }
                .map(\.endDelta)
            var d = followDeltas.max { abs($0) < abs($1) } ?? 0

            // Overlap: a moving task now overlaps this one — push it to start
            // when that task ends. Repeat until it lands somewhere clear,
            // since clearing one task can land it on another.
            var changed = true
            while changed {
                changed = false
                for p in planned {
                    let alreadyOverlapped = cs < p.e && ce > p.s
                    let ns = cs + d, ne = ce + d
                    if !alreadyOverlapped && ns < p.ne && ne > p.ns && p.ne - cs > d {
                        d = p.ne - cs
                        changed = true
                    }
                }
            }

            if d != 0 {
                result.append(Push(task: c, delta: d))
                planned.append(Planned(s: cs, e: ce, ns: cs + d, ne: ce + d, endDelta: d))
            }
        }
        return result
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

    private static func apply(_ pushes: [Push], impulseTypes: [ImpulseType]) {
        for p in pushes {
            shift([p.task], by: p.delta, impulseTypes: impulseTypes)
        }
    }

    /// Moves `tasks` by `delta` minutes and pushes the tasks after them,
    /// handling repeats. Returns everything that moved.
    @discardableResult
    static func move(_ tasks: [Task], by delta: Int, context: ModelContext, impulseTypes: [ImpulseType]) -> [Task] {
        guard delta != 0, !tasks.isEmpty else { return [] }
        let pushed = pushes(for: tasks, startDelta: delta, endDelta: delta, context: context)
        prepareRepeats(tasks + pushed.map(\.task), context: context)
        shift(tasks, by: delta, impulseTypes: impulseTypes)
        apply(pushed, impulseTypes: impulseTypes)
        try? context.save()
        return tasks + pushed.map(\.task)
    }

    /// Makes a task longer by `delta` minutes (end time moves, start stays)
    /// and pushes the tasks after it. Repeat tasks get their next occurrence
    /// created first, at the original time/length. Returns the extended task
    /// plus everything that moved.
    @discardableResult
    static func extend(_ task: Task, by delta: Int, context: ModelContext, impulseTypes: [ImpulseType]) -> [Task] {
        guard delta > 0, let end = minutes(task.endTime), minutes(task.startTime) != nil else { return [] }
        let pushed = pushes(for: [task], startDelta: 0, endDelta: delta, context: context)
        prepareRepeats([task] + pushed.map(\.task), context: context)

        let before = ImpulseRules.Snapshot(task)
        task.endTime = format(end + delta)
        ImpulseRules.reconcile(task, before: before, types: impulseTypes)

        apply(pushed, impulseTypes: impulseTypes)
        try? context.save()
        return [task] + pushed.map(\.task)
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

/// Swapping two pending timed tasks on the same day.
///
/// The block from the earlier task's start to the later task's end stays the
/// same. The two tasks keep their lengths and trade places; pending tasks
/// between them keep their lengths and gaps and slide by the difference in
/// length. Completed / not-completed tasks and tasks outside the block stay put.
/// e.g. A 12:30–1:00, B 1:00–1:20, C 1:30–2:20; swap A and C →
/// C 12:30–1:20, B 1:20–1:40, A 1:50–2:20.
enum TaskSwapper {
    struct Change {
        let task: Task
        let newStart: Int
        let newEnd: Int
        var newStartTime: String { TaskMover.format(newStart) }
        var newEndTime: String { TaskMover.format(newEnd) }
    }

    /// Pending timed tasks on the same day as `task` (including it), by start time.
    static func candidates(for task: Task, context: ModelContext) -> [Task] {
        guard let day = task.date else { return [] }
        return ((try? context.fetch(FetchDescriptor<Task>())) ?? [])
            .filter { t in
                guard let d = t.date, Calendar.current.isDate(d, inSameDayAs: day),
                      !t.completed, !t.notCompleted,
                      TaskMover.minutes(t.startTime) != nil, TaskMover.minutes(t.endTime) != nil else { return false }
                return true
            }
            .sorted { (TaskMover.minutes($0.startTime) ?? 0) < (TaskMover.minutes($1.startTime) ?? 0) }
    }

    /// What would change, without changing anything. Order: earlier slot first.
    static func plan(_ a: Task, _ b: Task, context: ModelContext) -> [Change] {
        guard a.id != b.id else { return [] }
        let (aS, aE) = span(a), (bS, bE) = span(b)
        let (first, fS, fE, second, sS, sE) = aS <= bS ? (a, aS, aE, b, bS, bE) : (b, bS, bE, a, aS, aE)
        let firstLen = fE - fS, secondLen = sE - sS
        let delta = secondLen - firstLen

        var changes = [Change(task: second, newStart: fS, newEnd: fS + secondLen)]
        for t in candidates(for: first, context: context) where t.id != first.id && t.id != second.id {
            let (s, e) = span(t)
            guard s >= fS && s < sS else { continue }
            changes.append(Change(task: t, newStart: s + delta, newEnd: e + delta))
        }
        changes.append(Change(task: first, newStart: sE - firstLen, newEnd: sE))
        return changes
    }

    /// Swaps `a` and `b` (see type docs). Repeat tasks get their next
    /// occurrence created first at the original time, then turn red.
    /// Returns every task whose time changed.
    @discardableResult
    static func swap(_ a: Task, _ b: Task, context: ModelContext, impulseTypes: [ImpulseType]) -> [Task] {
        let changes = plan(a, b, context: context).filter { c in
            let (s, e) = span(c.task)
            return s != c.newStart || e != c.newEnd
        }
        guard !changes.isEmpty else { return [] }
        TaskMover.prepareRepeats(changes.map(\.task), context: context)
        for c in changes {
            let before = ImpulseRules.Snapshot(c.task)
            c.task.startTime = c.newStartTime
            c.task.endTime = c.newEndTime
            ImpulseRules.reconcile(c.task, before: before, types: impulseTypes)
        }
        try? context.save()
        return changes.map(\.task)
    }

    private static func span(_ t: Task) -> (Int, Int) {
        let s = TaskMover.minutes(t.startTime) ?? 0
        let e = TaskMover.minutes(t.endTime) ?? s
        return (s, e < s ? e + 24 * 60 : e)
    }
}
