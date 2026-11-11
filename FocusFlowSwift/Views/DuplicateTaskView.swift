import SwiftUI
import SwiftData

/// Makes a copy of a task on a day and time you pick (one step, no clipboard).
struct DuplicateTaskView: View {
    let task: Task
    /// Called after the copy is saved.
    let onDone: (Task) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var day: Date
    @State private var start: Date
    @State private var withSubtasks = true
    @State private var keepRepeat = false

    private let duration: Int
    private var isTimed: Bool { !task.startTime.isEmpty && !task.endTime.isEmpty }
    private var end: Date { start.addingTimeInterval(Double(duration) * 60) }

    init(task: Task, onDone: @escaping (Task) -> Void) {
        self.task = task
        self.onDone = onDone
        let range = TaskSplitter.range(of: task)
        duration = range.map { $0.end - $0.start } ?? 0
        let day = (task.date ?? Date()).startOfDay
        _day = State(initialValue: day)
        // Default: right after the original ends.
        _start = State(initialValue: day.atClock(minutes: (range?.end ?? 9 * 60) % 1440))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Task", value: task.title)
                    if isTimed {
                        LabeledContent("Original", value: "\(formatTimeToAMPM(task.startTime)) – \(formatTimeToAMPM(task.endTime))")
                    }
                }

                Section {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                    if isTimed {
                        DatePicker("Starts at", selection: $start, displayedComponents: .hourAndMinute)
                        LabeledContent("Ends at", value: end.formatted(date: .omitted, time: .shortened))
                        Button("Same time as original") {
                            start = day.atClock(minutes: TaskSplitter.range(of: task)?.start ?? 0)
                        }
                    }
                } header: {
                    Text("Copy to")
                } footer: {
                    if isTimed { Text("Same length: \(duration) min") }
                }

                if isTimed {
                    TaskConflictWarning(date: day, start: start, end: end)
                }

                Section {
                    Toggle("Copy subtasks", isOn: $withSubtasks)
                    if task.repeatAgain != nil {
                        Toggle("Keep repeat (habit)", isOn: $keepRepeat)
                    }
                } footer: {
                    Text("The copy keeps the title, tags, notes, priority, goal and info. It starts not done, with no time spent.")
                }
            }
            .navigationTitle("Duplicate task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Duplicate") { save() }
                }
            }
        }
    }

    private func save() {
        var startTime = "", endTime = ""
        if isTimed {
            let c = Calendar.current.dateComponents([.hour, .minute], from: start)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            startTime = TaskSplitter.hm(m)
            endTime = TaskSplitter.hm(m + duration)
        }
        let copy = Task(
            title: task.title,
            taskDescription: task.taskDescription,
            startTime: startTime,
            endTime: endTime,
            weight: task.weight,
            notes: task.notes,
            date: task.date == nil ? nil : day.startOfDay,
            repeatAgain: keepRepeat ? task.repeatAgain : nil,
            priority: task.priority,
            copySubtasks: task.copySubtasks,
            whyStatement: task.whyStatement,
            whyStatementPinned: task.whyStatementPinned,
            goal: task.goal,
            info: task.info,
            backlogFolder: task.date == nil ? task.backlogFolder : nil
        )
        if keepRepeat {
            task.copyRepeat(to: copy)
            copy.repeatSeriesID = UUID()   // its own series, not a second copy of this one
        }
        copy.impulseTypeID = task.impulseTypeID
        modelContext.insert(copy)
        if withSubtasks {
            SubtaskOrder.copyAll(from: task, to: copy, context: modelContext)
        }
        try? modelContext.save()
        onDone(copy)
        dismiss()
    }
}
