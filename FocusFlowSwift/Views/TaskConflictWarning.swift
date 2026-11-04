import SwiftUI
import SwiftData

/// Orange warning listing the timed tasks that overlap a start–end time on a
/// day. Shown while creating or editing a task; it doesn't block saving.
struct TaskConflictWarning: View {
    let date: Date
    let start: Date
    let end: Date
    /// The task being edited, so it doesn't conflict with itself.
    var excluding: UUID? = nil

    @Query private var tasks: [Task]

    init(date: Date, start: Date, end: Date, excluding: UUID? = nil) {
        self.date = date
        self.start = start
        self.end = end
        self.excluding = excluding
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        _tasks = Query(filter: #Predicate<Task> { t in
            if let d = t.date { d >= dayStart && d < dayEnd } else { false }
        })
    }

    private struct Conflict: Identifiable {
        let task: Task
        let overlap: Int
        var id: UUID { task.id }
    }

    /// Minutes since midnight, with an end at or before the start running past midnight.
    private static func range(_ start: Int, _ end: Int) -> (Int, Int) {
        (start, end <= start ? end + 24 * 60 : end)
    }

    private var conflicts: [Conflict] {
        let cal = Calendar.current
        let s = cal.component(.hour, from: start) * 60 + cal.component(.minute, from: start)
        let e = cal.component(.hour, from: end) * 60 + cal.component(.minute, from: end)
        let (ns, ne) = Self.range(s, e)
        guard ne > ns else { return [] }
        return tasks.compactMap { t in
            guard t.id != excluding,
                  let ts = ImpulseRules.minutes(from: t.startTime),
                  let te = ImpulseRules.minutes(from: t.endTime) else { return nil }
            let (os, oe) = Self.range(ts, te)
            let overlap = min(ne, oe) - max(ns, os)
            return overlap > 0 ? Conflict(task: t, overlap: overlap) : nil
        }
        .sorted { (ImpulseRules.minutes(from: $0.task.startTime) ?? 0) < (ImpulseRules.minutes(from: $1.task.startTime) ?? 0) }
    }

    var body: some View {
        let list = conflicts
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(list.count == 1 ? "Overlaps 1 task" : "Overlaps \(list.count) tasks",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("This task: \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(list) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.task.title.isEmpty ? "Untitled task" : c.task.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                            Text("\(formatTimeToAMPM(c.task.startTime)) – \(formatTimeToAMPM(c.task.endTime)) · overlaps \(PlannerRules.formatMinutes(Double(c.overlap)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if c.task.completed {
                            Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                        }
                    }
                }
                Text("You can still save; overlapping tasks show side by side.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
        }
    }
}
