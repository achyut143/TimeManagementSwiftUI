import SwiftUI
import SwiftData

/// Shows a repeat task's notes one week at a time: every day in the current
/// 7-day window is listed with whatever notes that occurrence has, and
/// Previous/Next shift the whole window back or forward by 7 days. Each
/// day's notes can be edited in place by tapping Edit on that row.
struct TaskNotesPagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// The task whose notes were requested. Used to match other occurrences
    /// (same title) and to anchor the initial window on its date.
    let task: Task

    /// The last (most recent) day of the currently displayed 7-day window.
    @State private var windowEnd: Date = Date()
    /// All tasks sharing the anchor task's title, loaded once and filtered
    /// per-window in `windowInstances` as the user pages back/forward.
    @State private var allMatchingTasks: [Task] = []

    @State private var editingTaskID: UUID?
    @State private var editText: String = ""

    private var calendar: Calendar { Calendar.current }

    private var windowStart: Date {
        calendar.date(byAdding: .day, value: -6, to: windowEnd) ?? windowEnd
    }

    /// The 7 days in the window, most recent first.
    private var days: [Date] {
        (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: windowEnd)
        }
    }

    private var windowInstances: [Task] {
        allMatchingTasks.filter { candidate in
            guard let date = candidate.date else { return false }
            let day = calendar.startOfDay(for: date)
            return day >= windowStart && day <= windowEnd
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                pagerHeader

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            dayRow(for: day)
                            Divider()
                        }
                    }
                    .padding()
                }
                .id(windowEnd)
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { loadMatches() }
    }

    // MARK: - Header

    private var pagerHeader: some View {
        VStack(spacing: 6) {
            Text(task.title)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Button {
                    shiftWindow(by: -7)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Previous 7")
                    }
                }

                Spacer()

                Text("\(windowStart.formatted(date: .abbreviated, time: .omitted)) – \(windowEnd.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    shiftWindow(by: 7)
                } label: {
                    HStack(spacing: 4) {
                        Text("Next 7")
                        Image(systemName: "chevron.right")
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Rows

    private func dayRow(for day: Date) -> some View {
        let dayInstances = windowInstances.filter { calendar.isDate($0.date ?? .distantPast, inSameDayAs: day) }

        return VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .fontWeight(.semibold)

            if dayInstances.isEmpty {
                Text("No task on this day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(dayInstances, id: \.id) { instance in
                    instanceRow(instance)
                }
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func instanceRow(_ instance: Task) -> some View {
        if editingTaskID == instance.id {
            VStack(alignment: .leading, spacing: 8) {
                RichTextEditor(text: $editText)
                    .frame(height: 160)
                HStack {
                    Button("Cancel") { editingTaskID = nil }
                    Spacer()
                    Button("Save") { saveEdit(for: instance) }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !instance.taskDescription.isEmpty {
                    Text(instance.taskDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let notes = instance.notes, !notes.isEmpty {
                    Text(notes)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No notes yet")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                Button {
                    editingTaskID = instance.id
                    editText = instance.notes ?? ""
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(8)
        }
    }

    // MARK: - Data

    private func loadMatches() {
        windowEnd = calendar.startOfDay(for: task.date ?? Date())

        let title = task.title
        let descriptor = FetchDescriptor<Task>(predicate: #Predicate<Task> { $0.title == title })
        allMatchingTasks = (try? modelContext.fetch(descriptor)) ?? [task]
    }

    private func shiftWindow(by days: Int) {
        editingTaskID = nil
        if let newEnd = calendar.date(byAdding: .day, value: days, to: windowEnd) {
            windowEnd = newEnd
        }
    }

    private func saveEdit(for instance: Task) {
        instance.notes = editText.isEmpty ? nil : editText
        try? modelContext.save()
        editingTaskID = nil
    }
}
