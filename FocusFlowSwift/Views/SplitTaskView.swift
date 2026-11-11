import SwiftUI
import SwiftData

/// Splits a task in two at a time you pick, or at the red line (now).
struct SplitTaskView: View {
    let task: Task
    /// Called after a successful split with the new second part.
    let onSplit: (Task) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    private var range: (start: Int, end: Int)? { TaskSplitter.range(of: task) }
    private var nowMinute: Int? { TaskSplitter.splitMinute(for: task) }

    /// The picked time as minutes from the task's midnight (past 1440 when the
    /// task runs past midnight and the pick is after midnight).
    private var pickedMinute: Int? {
        guard let range else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        var m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if m <= range.start && range.end > 1440 { m += 1440 }
        return m
    }

    private var isValid: Bool {
        guard let range, let m = pickedMinute else { return false }
        return m > range.start && m < range.end
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Task", value: task.title)
                    LabeledContent("Time", value: "\(formatTimeToAMPM(task.startTime)) – \(formatTimeToAMPM(task.endTime))")
                }

                Section {
                    DatePicker("Split at", selection: $time, displayedComponents: .hourAndMinute)
                    if let m = nowMinute {
                        Button {
                            time = Date().startOfDay.atClock(minutes: m % 1440)
                        } label: {
                            Label("Use the red line (\(formatTimeToAMPM(TaskSplitter.hm(m))))", systemImage: "clock.badge")
                        }
                    }
                } footer: {
                    if !isValid {
                        Text("Pick a time between the task's start and end.")
                            .foregroundStyle(.red)
                    }
                }

                if isValid, let range, let m = pickedMinute {
                    Section("Result") {
                        partRow(1, from: range.start, to: m)
                        partRow(2, from: m, to: range.end)
                    }
                }

                Section {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Split task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { split() }
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: setDefault)
        }
        .presentationDetents([.medium, .large])
    }

    private func partRow(_ n: Int, from: Int, to: Int) -> some View {
        HStack {
            Text("Part \(n)")
            Spacer()
            Text("\(formatTimeToAMPM(TaskSplitter.hm(from))) – \(formatTimeToAMPM(TaskSplitter.hm(to)))")
                .monospacedDigit()
            Text("\(to - from)m")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var note: String {
        var text = "Part 1 keeps its status, notes, subtasks and files. Part 2 gets the same title, notes, priority, goal and tags."
        if task.repeatAgain != nil {
            text += task.reassign
                ? " The next occurrence is already handled (repeat is red)."
                : " The next occurrence is created now and the repeat turns red on both parts."
        }
        return text
    }

    /// Red line if it's inside the task, otherwise the middle (on a 5-minute mark).
    private func setDefault() {
        guard let range else { return }
        var m = nowMinute ?? (range.start + (range.end - range.start) / 2)
        if nowMinute == nil {
            let rounded = m - m % 5
            if rounded > range.start { m = rounded }
        }
        time = Date().startOfDay.atClock(minutes: m % 1440)
    }

    private func split() {
        guard let m = pickedMinute,
              let second = TaskSplitter.split(task, atMinute: m, context: modelContext) else { return }
        onSplit(second)
        dismiss()
    }
}
