import SwiftUI
import SwiftData

/// A repeat task (`Task.repeatAgain != nil`) is supposed to keep generating
/// its next occurrence forever — but that chain only continues when the
/// current occurrence actually gets completed/processed (see
/// `TasksCalendarView.createRepeatTask`/`createIncompleteTask`). If the last
/// occurrence in a chain is ever deleted, ignored, or the repeat task itself
/// is removed mid-chain, nothing generates the next one and the "habit"
/// silently goes stale — it just stops showing up anywhere, with no
/// indication anything's wrong.
///
/// This view finds every repeat-task chain whose most recent dated task is
/// in the past (no task for today or any future date exists), so those
/// orphaned habits are surfaced instead of quietly disappearing, with the
/// same Archive/Delete actions the Habit Tracker already offers per-habit
/// (`HabitDashboardView.archiveHabit`/`deleteHabit`, both reusing
/// `HabitArchiveService`).
struct StaleHabitsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]

    @State private var habitPendingAction: String?
    @State private var showActionDialog = false
    @State private var habitPendingDeleteConfirmation: String?

    private struct StaleHabit: Identifiable {
        var id: String { title }
        let title: String
        let lastTaskDate: Date
        let lastTaskCompleted: Bool
        let lastCompletedDate: Date?
        let totalTasks: Int
        let completedTasks: Int
    }

    private var staleHabits: [StaleHabit] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let repeatTasks = tasks.filter { $0.repeatAgain != nil }
        let grouped = Dictionary(grouping: repeatTasks, by: { $0.title })

        return grouped.compactMap { title, habitTasks -> StaleHabit? in
            let dated = habitTasks.filter { $0.date != nil }
            guard let lastTask = dated.max(by: { $0.date! < $1.date! }) else { return nil }
            // Has a task scheduled today or later — the chain is still alive.
            guard lastTask.date! < startOfToday else { return nil }

            let completed = habitTasks.filter { $0.completed }
            let lastCompletedDate = completed.compactMap { $0.date }.max()

            return StaleHabit(
                title: title,
                lastTaskDate: lastTask.date!,
                lastTaskCompleted: lastTask.completed,
                lastCompletedDate: lastCompletedDate,
                totalTasks: habitTasks.count,
                completedTasks: completed.count
            )
        }
        .sorted { $0.lastTaskDate > $1.lastTaskDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if staleHabits.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("No Stale Repeat Tasks")
                            .font(.headline)
                        Text("Every repeating task has a current or upcoming occurrence.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(staleHabits) { habit in
                                row(habit)
                            }
                        } footer: {
                            Text("A repeat task only keeps generating its next occurrence when the current one gets completed or marked not completed. These have no task scheduled today or later — something broke the chain.")
                        }
                    }
                }
            }
            .navigationTitle("Stale Repeat Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Habit Actions", isPresented: $showActionDialog, titleVisibility: .visible) {
                Button("Archive") {
                    if let name = habitPendingAction { archiveHabit(name) }
                }
                Button("Delete", role: .destructive) {
                    habitPendingDeleteConfirmation = habitPendingAction
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose an action for \"\(habitPendingAction ?? "")\":\n\n• Archive: Save statistics and remove from active habits\n• Delete: Permanently remove habit and all its tasks")
            }
            .alert(
                "Delete \"\(habitPendingDeleteConfirmation ?? "")\"?",
                isPresented: Binding(
                    get: { habitPendingDeleteConfirmation != nil },
                    set: { if !$0 { habitPendingDeleteConfirmation = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { habitPendingDeleteConfirmation = nil }
                Button("Delete", role: .destructive) {
                    if let name = habitPendingDeleteConfirmation { deleteHabit(name) }
                    habitPendingDeleteConfirmation = nil
                }
            } message: {
                Text("This permanently removes all of its tasks, including completed history. This can't be undone — consider Archive instead if you want to keep the statistics.")
            }
        }
    }

    private func row(_ habit: StaleHabit) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.title)
                    .font(.headline)

                if let lastCompleted = habit.lastCompletedDate {
                    Text("Last completed \(lastCompleted.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Never completed")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Last scheduled \(habit.lastTaskDate.formatted(date: .abbreviated, time: .omitted)) (\(daysAgo(habit.lastTaskDate)) days ago)\(habit.lastTaskCompleted ? "" : " — never resolved")")
                    .font(.caption2)
                    .foregroundStyle(.red)

                Text("\(habit.completedTasks)/\(habit.totalTasks) completed overall")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    archiveHabit(habit.title)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                Button(role: .destructive) {
                    habitPendingDeleteConfirmation = habit.title
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            habitPendingAction = habit.title
            showActionDialog = true
        }
    }

    private func daysAgo(_ date: Date) -> Int {
        let start = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
    }

    // Mirrors HabitDashboardView.archiveHabit(_:) exactly — same service,
    // same "archive then delete the source tasks" sequence — so a habit
    // archived from here shows up in ArchivedHabitsView identically to one
    // archived from the Habit Tracker itself.
    private func archiveHabit(_ habitName: String) {
        if let archivedHabit = HabitArchiveService.archiveHabit(habitName: habitName, tasks: tasks, context: modelContext) {
            modelContext.insert(archivedHabit)
            let tasksToDelete = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }
            for task in tasksToDelete {
                modelContext.delete(task)
            }
            try? modelContext.save()
        }
    }

    private func deleteHabit(_ habitName: String) {
        let tasksToDelete = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        try? modelContext.save()
    }
}
