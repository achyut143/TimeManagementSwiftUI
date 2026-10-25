import SwiftUI
import SwiftData

/// Task Actions → Swap. Lists the day's pending timed tasks (time on the
/// left, name on the right); pick one to see a before/after preview, then
/// swap. Rules live in `TaskSwapper`.
struct SwapTaskView: View {
    let task: Task
    /// Called after a swap, so the caller can close too.
    var onSwapped: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ImpulseType.sortOrder) private var impulseTypes: [ImpulseType]
    @State private var selected: Task?

    var body: some View {
        let tasks = TaskSwapper.candidates(for: task, context: modelContext)
        NavigationStack {
            List {
                Section {
                    if tasks.count < 2 {
                        Text("No other pending timed tasks on this day.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(tasks) { t in
                        row(t)
                    }
                } header: {
                    Text("Swap \"\(task.title)\" with…")
                        .textCase(nil)
                }

                if let selected {
                    previewSection(with: selected)
                }
            }
            .navigationTitle("Swap Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Swap") { performSwap() }
                        .disabled(selected == nil)
                }
            }
        }
    }

    private func timeRange(_ start: String, _ end: String) -> String {
        "\(formatTimeToAMPM(start)) – \(formatTimeToAMPM(end))"
    }

    private func row(_ t: Task) -> some View {
        let isSelf = t.id == task.id
        let isPicked = selected?.id == t.id
        return Button {
            selected = isPicked ? nil : t
        } label: {
            HStack(spacing: 12) {
                Text(timeRange(t.startTime, t.endTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                Text(t.title)
                    .font(.subheadline.weight(isSelf || isPicked ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                if isSelf {
                    Text("This task")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                } else if isPicked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.purple)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelf)
        .listRowBackground(isSelf ? Color.blue.opacity(0.08) : (isPicked ? Color.purple.opacity(0.1) : nil))
    }

    private func previewSection(with other: Task) -> some View {
        let changes = TaskSwapper.plan(task, other, context: modelContext)
        let repeats = changes.filter { $0.task.repeatAgain != nil && !$0.task.reassign }.count
        return Section {
            ForEach(changes, id: \.task.id) { c in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeRange(c.newStartTime, c.newEndTime))
                            .font(.caption.monospacedDigit().weight(.semibold))
                        Text("was \(timeRange(c.task.startTime, c.task.endTime))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .leading)
                    Text(c.task.title)
                        .font(.subheadline)
                        .lineLimit(2)
                }
            }
        } header: {
            Text("After swap")
        } footer: {
            Text("The two tasks keep their lengths and trade places. Tasks between them keep their lengths and gaps and slide to make room. Completed tasks and tasks outside this range stay put."
                 + (repeats > 0 ? " Repeat tasks get their next day created first at the original time, then their repeat icon turns red." : ""))
        }
    }

    private func performSwap() {
        guard let selected else { return }
        let changed = TaskSwapper.swap(task, selected, context: modelContext, impulseTypes: impulseTypes)
        NotificationCenter.default.post(name: NSNotification.Name("TasksSnoozed"), object: changed.map(\.id))
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
        onSwapped()
        dismiss()
    }
}
