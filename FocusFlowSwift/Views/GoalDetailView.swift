import SwiftUI
import SwiftData

struct GoalDetailView: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var modelContext

    let filterFrom: Date
    let filterTo: Date

    @State private var selectedTaskForActions: Task?
    @State private var showTaskActions = false
    @State private var showEditGoal = false
    @State private var reassignHabitName: String? = nil

    private var allGoalTasks: [Task] {
        (goal.tasks ?? []).filter { task in
            guard let d = task.date else { return false }
            return d >= filterFrom && d <= filterTo
        }.sorted {
            let d0 = $0.date ?? .distantPast
            let d1 = $1.date ?? .distantPast
            return d0 > d1
        }
    }

    private var habitTasks: [Task] {
        allGoalTasks.filter { $0.repeatAgain != nil }
    }

    private var regularTasks: [Task] {
        allGoalTasks.filter { $0.repeatAgain == nil }
    }

    // Groups habit tasks by title (case-insensitive). Tasks within each group stay newest-first.
    private var groupedHabitTasks: [(name: String, tasks: [Task])] {
        var groups: [String: (name: String, tasks: [Task])] = [:]
        for task in habitTasks {
            let key = task.title.lowercased().trimmingCharacters(in: .whitespaces)
            if groups[key] == nil {
                groups[key] = (name: task.title, tasks: [task])
            } else {
                groups[key]!.tasks.append(task)
            }
        }
        return groups.values
            .map { (name: $0.name, tasks: $0.tasks.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                goalHeader
                    .padding()

                if !habitTasks.isEmpty {
                    // Section label — not an accordion, just a header
                    HStack {
                        Text("HABITS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(groupedHabitTasks.count) habit\(groupedHabitTasks.count == 1 ? "" : "s") · \(habitTasks.count) entries")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))

                    ForEach(groupedHabitTasks, id: \.name) { group in
                        HabitAccordionRow(
                            habitName: group.name,
                            tasks: group.tasks,
                            onTaskTap: { task in
                                selectedTaskForActions = task
                                showTaskActions = true
                            },
                            onReassignTap: { reassignHabitName = group.name }
                        )
                        Divider()
                    }
                }

                if !regularTasks.isEmpty {
                    regularSection
                }

                if allGoalTasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Assign tasks to this goal from the task edit screen.")
                    )
                    .padding(.top, 40)
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showEditGoal = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showTaskActions) {
            if let task = selectedTaskForActions {
                TaskActionsView(
                    task: task,
                    selectedDate: task.date ?? Date(),
                    onTaskDeleted: {}
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showEditGoal) {
            EditGoalView(goal: goal)
        }
        .sheet(isPresented: Binding(
            get: { reassignHabitName != nil },
            set: { if !$0 { reassignHabitName = nil } }
        )) {
            if let name = reassignHabitName,
               let group = groupedHabitTasks.first(where: { $0.name == name }) {
                HabitGoalReassignSheet(habitName: name, tasks: group.tasks, currentGoal: goal)
            }
        }
    }

    private var goalHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !goal.goalDescription.isEmpty {
                Text(goal.goalDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(allGoalTasks.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(allGoalTasks.filter { $0.completed }.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                    Text("Done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                let pct: Double = allGoalTasks.isEmpty ? 0 : Double(allGoalTasks.filter { $0.completed }.count) / Double(allGoalTasks.count) * 100
                GoalProgressRing(percentage: pct)
                    .frame(width: 56, height: 56)
            }

            GeometryReader { geometry in
                let pct: Double = allGoalTasks.isEmpty ? 0 : Double(allGoalTasks.filter { $0.completed }.count) / Double(allGoalTasks.count) * 100
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(pct / 100.0), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: pct)
                }
            }
            .frame(height: 8)
        }
    }

    private var progressColor: Color {
        let pct = allGoalTasks.isEmpty ? 0.0 : Double(allGoalTasks.filter { $0.completed }.count) / Double(allGoalTasks.count) * 100
        if pct >= 75 { return .green }
        if pct >= 40 { return .orange }
        return .red
    }

    private var regularSection: some View {
        Section {
            LazyVStack(spacing: 0) {
                HStack {
                    Label("One-time Tasks", systemImage: "checkmark.square")
                        .font(.headline)
                    Spacer()
                    Text("\(regularTasks.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple)
                        .clipShape(Capsule())
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemGroupedBackground))

                ForEach(regularTasks) { task in
                    GoalTaskRow(task: task) {
                        selectedTaskForActions = task
                        showTaskActions = true
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Habit Accordion Row

struct HabitAccordionRow: View {
    let habitName: String
    let tasks: [Task]
    let onTaskTap: (Task) -> Void
    let onReassignTap: () -> Void

    @State private var isExpanded = false
    @State private var visibleCount = 10

    private var visibleTasks: [Task] { Array(tasks.prefix(visibleCount)) }
    private var remainingCount: Int { max(0, tasks.count - visibleCount) }

    private var doneCount: Int { tasks.filter { $0.completed }.count }
    private var donePercentage: Int {
        tasks.isEmpty ? 0 : Int(Double(doneCount) / Double(tasks.count) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: tapping the row expands; the move button is a separate tap target
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 3, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(habitName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(tasks.count) \(tasks.count == 1 ? "entry" : "entries")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(doneCount) done · \(donePercentage)%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(donePercentage >= 75 ? .green : donePercentage >= 40 ? .orange : .red)
                    }
                }

                Spacer()

                if isExpanded && tasks.count > 10 {
                    Text("showing \(min(visibleCount, tasks.count)) of \(tasks.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button(action: onReassignTap) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            }

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        GoalTaskRow(task: task) { onTaskTap(task) }
                        Divider().padding(.leading, 16)
                    }

                    if remainingCount > 0 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                visibleCount += 10
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.caption)
                                Text("Load \(min(10, remainingCount)) more")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("· \(remainingCount) remaining")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - Goal Task Row

struct GoalTaskRow: View {
    let task: Task
    let onTap: () -> Void

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "P1": return .red
        case "P2": return .orange
        case "P3": return .blue
        case "P4": return .gray
        default: return .blue
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                priorityStripe
                    .frame(width: 4)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: task.completed ? "checkmark.circle.fill" : (task.notCompleted ? "xmark.circle.fill" : "circle"))
                            .foregroundStyle(task.completed ? .green : (task.notCompleted ? .red : .secondary))
                        Text(task.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .strikethrough(task.completed, color: .secondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 6) {
                        if let date = task.date {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        if !task.startTime.isEmpty {
                            Text("\(task.startTime)–\(task.endTime)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if task.repeatAgain != nil {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        Text("W: \(String(format: "%.1f", task.weight))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    private var priorityStripe: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(priorityColor(task.priority))
    }
}

struct UndefinedGoalDetailView: View {
    let filterFrom: Date
    let filterTo: Date

    @Query private var allTasks: [Task]
    @State private var selectedTaskForActions: Task?
    @State private var showTaskActions = false
    @State private var reassignHabitName: String? = nil

    private var undefinedTasks: [Task] {
        allTasks
            .filter { task in
                guard task.goal == nil, let d = task.date else { return false }
                return d >= filterFrom && d <= filterTo
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    private var habitTasks: [Task] { undefinedTasks.filter { $0.repeatAgain != nil } }
    private var regularTasks: [Task] { undefinedTasks.filter { $0.repeatAgain == nil } }

    private var groupedHabitTasks: [(name: String, tasks: [Task])] {
        var groups: [String: (name: String, tasks: [Task])] = [:]
        for task in habitTasks {
            let key = task.title.lowercased().trimmingCharacters(in: .whitespaces)
            if groups[key] == nil {
                groups[key] = (name: task.title, tasks: [task])
            } else {
                groups[key]!.tasks.append(task)
            }
        }
        return groups.values
            .map { (name: $0.name, tasks: $0.tasks.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if undefinedTasks.isEmpty {
                    ContentUnavailableView(
                        "All Assigned",
                        systemImage: "checkmark.seal",
                        description: Text("All tasks have been assigned to a goal.")
                    )
                    .padding(.top, 40)
                } else {
                    if !habitTasks.isEmpty {
                        HStack {
                            Text("HABITS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(groupedHabitTasks.count) habit\(groupedHabitTasks.count == 1 ? "" : "s") · \(habitTasks.count) entries")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGroupedBackground))

                        ForEach(groupedHabitTasks, id: \.name) { group in
                            HabitAccordionRow(
                                habitName: group.name,
                                tasks: group.tasks,
                                onTaskTap: { task in
                                    selectedTaskForActions = task
                                    showTaskActions = true
                                },
                                onReassignTap: { reassignHabitName = group.name }
                            )
                            Divider()
                        }
                    }
                    if !regularTasks.isEmpty {
                        regularSection
                    }
                }
            }
        }
        .navigationTitle("No Goal")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showTaskActions) {
            if let task = selectedTaskForActions {
                TaskActionsView(
                    task: task,
                    selectedDate: task.date ?? Date(),
                    onTaskDeleted: {}
                )
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: Binding(
            get: { reassignHabitName != nil },
            set: { if !$0 { reassignHabitName = nil } }
        )) {
            if let name = reassignHabitName,
               let group = groupedHabitTasks.first(where: { $0.name == name }) {
                HabitGoalReassignSheet(habitName: name, tasks: group.tasks, currentGoal: nil)
            }
        }
    }

    private var regularSection: some View {
        VStack(spacing: 0) {
            HStack {
                Label("One-time Tasks", systemImage: "checkmark.square")
                    .font(.headline)
                Spacer()
                Text("\(regularTasks.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple)
                    .clipShape(Capsule())
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            LazyVStack(spacing: 0) {
                ForEach(regularTasks) { task in
                    GoalTaskRow(task: task) {
                        selectedTaskForActions = task
                        showTaskActions = true
                    }
                    Divider().padding(.leading, 16)
                }
            }
        }
    }
}

// MARK: - Habit Goal Reassign Sheet

struct HabitGoalReassignSheet: View {
    let habitName: String
    let tasks: [Task]
    let currentGoal: Goal?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Goal.name) private var allGoals: [Goal]

    var body: some View {
        NavigationStack {
            List {
                noGoalSection
                goalListSection
            }
            .navigationTitle("Move \"\(habitName)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var noGoalSection: some View {
        Section {
            Button { reassign(to: nil) } label: {
                HStack {
                    Label("No Goal", systemImage: "tray").foregroundStyle(.primary)
                    Spacer()
                    if currentGoal == nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var goalListSection: some View {
        Section("Move to Goal") {
            ForEach(allGoals) { goal in
                goalRow(goal)
            }
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        Button { reassign(to: goal) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).foregroundStyle(.primary)
                    if !goal.goalDescription.isEmpty {
                        Text(goal.goalDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if currentGoal?.id == goal.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func reassign(to goal: Goal?) {
        for task in tasks {
            task.goal = goal
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Edit Goal View

struct EditGoalView: View {
    @Bindable var goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var description: String

    init(goal: Goal) {
        self.goal = goal
        _name = State(initialValue: goal.name)
        _description = State(initialValue: goal.goalDescription)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Goal Details") {
                    TextField("Goal Name", text: $name)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goal.name = name.trimmingCharacters(in: .whitespaces)
                        goal.goalDescription = description.trimmingCharacters(in: .whitespaces)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
