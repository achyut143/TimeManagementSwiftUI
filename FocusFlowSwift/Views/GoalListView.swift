import SwiftUI
import SwiftData

struct GoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.name) private var goals: [Goal]
    @Query private var allTasks: [Task]

    @State private var showCreateGoal = false
    @State private var goalToDelete: Goal? = nil
    @State private var showDeleteConfirmation = false

    // Persisted filter dates (stored as epoch seconds; 0 = use default)
    @AppStorage("goalFilter.fromTimestamp") private var fromTimestamp: Double = 0
    @AppStorage("goalFilter.toTimestamp") private var toTimestamp: Double = 0

    private var filterFrom: Date {
        fromTimestamp == 0 ? Self.defaultFromDate : Date(timeIntervalSince1970: fromTimestamp)
    }
    private var filterTo: Date {
        toTimestamp == 0 ? Date() : Date(timeIntervalSince1970: toTimestamp)
    }
    private var filterToEndOfDay: Date {
        Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: filterTo) ?? filterTo
    }

    private static var defaultFromDate: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private var undefinedFilteredCount: Int {
        allTasks.filter { task in
            guard task.goal == nil, let d = task.date else { return false }
            return d >= filterFrom && d <= filterToEndOfDay
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Date filter bar
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("", selection: Binding(
                    get: { filterFrom },
                    set: { fromTimestamp = $0.timeIntervalSince1970 }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

                Text("→")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DatePicker("", selection: Binding(
                    get: { filterTo },
                    set: { toTimestamp = $0.timeIntervalSince1970 }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button("Reset") {
                    fromTimestamp = 0
                    toTimestamp = 0
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            List {
                Section("Goals") {
                    ForEach(goals) { goal in
                        NavigationLink(destination: GoalDetailView(goal: goal, filterFrom: filterFrom, filterTo: filterToEndOfDay)) {
                            GoalRowView(goal: goal, filterFrom: filterFrom, filterTo: filterToEndOfDay)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                goalToDelete = goal
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Section("Unassigned") {
                    NavigationLink(destination: UndefinedGoalDetailView(filterFrom: filterFrom, filterTo: filterToEndOfDay)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("No Goal")
                                    .font(.headline)
                                Text("Tasks without a goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(undefinedFilteredCount)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateGoal = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCreateGoal) {
            CreateGoalView()
        }
        .confirmationDialog(
            "Delete \"\(goalToDelete?.name ?? "Goal")\"?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Goal, Keep Tasks", role: .destructive) {
                if let goal = goalToDelete { deleteGoal(goal, deleteTasks: false) }
                goalToDelete = nil
            }
            Button("Delete Goal & All Its Tasks", role: .destructive) {
                if let goal = goalToDelete { deleteGoal(goal, deleteTasks: true) }
                goalToDelete = nil
            }
            Button("Cancel", role: .cancel) { goalToDelete = nil }
        } message: {
            if let goal = goalToDelete {
                let count = goal.taskCount
                Text("This goal has \(count) task\(count == 1 ? "" : "s"). Choose whether to keep them (moved to Unassigned) or delete them too.")
            }
        }
    }

    private func deleteGoal(_ goal: Goal, deleteTasks: Bool) {
        if deleteTasks {
            for task in goal.tasks ?? [] {
                modelContext.delete(task)
            }
        }
        modelContext.delete(goal)
        try? modelContext.save()
    }
}

struct GoalRowView: View {
    let goal: Goal
    let filterFrom: Date
    let filterTo: Date

    private var filteredTasks: [Task] {
        (goal.tasks ?? []).filter { task in
            guard let d = task.date else { return false }
            return d >= filterFrom && d <= filterTo
        }
    }
    private var filteredTotal: Int { filteredTasks.count }
    private var filteredDone: Int { filteredTasks.filter { $0.completed }.count }
    private var filteredPercentage: Double {
        guard filteredTotal > 0 else { return 0 }
        return Double(filteredDone) / Double(filteredTotal) * 100
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name)
                    .font(.headline)
                if !goal.goalDescription.isEmpty {
                    Text(goal.goalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Label("\(filteredTotal)", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(filteredDone) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            GoalProgressRing(percentage: filteredPercentage)
        }
        .padding(.vertical, 4)
    }
}

struct GoalProgressRing: View {
    let percentage: Double

    private var color: Color {
        if percentage >= 75 { return .green }
        if percentage >= 40 { return .orange }
        return .red
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(percentage / 100.0))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: percentage)
            Text("\(Int(percentage))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }
}

struct CreateGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var description = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Goal Details") {
                    TextField("Goal Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGoal()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createGoal() {
        let goal = Goal(
            name: name.trimmingCharacters(in: .whitespaces),
            goalDescription: description.trimmingCharacters(in: .whitespaces)
        )
        modelContext.insert(goal)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        GoalListView()
    }
    .modelContainer(for: [Goal.self, Task.self], inMemory: true)
}
