import SwiftUI
import SwiftData

struct GoalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Goal.name) private var goals: [Goal]
    @Query private var allTasks: [Task]

    @State private var showCreateGoal = false
    @State private var selectedGoalForDetail: Goal?
    @State private var showUndefinedGoal = false

    var undefinedTaskCount: Int {
        allTasks.filter { $0.goal == nil }.count
    }

    var body: some View {
        List {
            Section("Goals") {
                ForEach(goals) { goal in
                    NavigationLink(destination: GoalDetailView(goal: goal)) {
                        GoalRowView(goal: goal)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteGoal(goal)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Section("Unassigned") {
                NavigationLink(destination: UndefinedGoalDetailView()) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("No Goal")
                                .font(.headline)
                            Text("Tasks without a goal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(undefinedTaskCount)")
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
    }

    private func deleteGoal(_ goal: Goal) {
        modelContext.delete(goal)
        try? modelContext.save()
    }
}

struct GoalRowView: View {
    let goal: Goal

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
                    Label("\(goal.taskCount)", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(goal.completedTaskCount) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            GoalProgressRing(percentage: goal.completionPercentage)
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
