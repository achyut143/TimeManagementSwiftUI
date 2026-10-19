import SwiftUI
import SwiftData

/// Day / week / month / quarter goals with upward links and carry-over.
struct PeriodGoalsView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [PeriodGoal]

    @State private var period: GoalPeriod = .week
    @State private var periodStart: Date = Date()
    @State private var newTitle = ""

    init(date: Date, period: GoalPeriod = .week) {
        self.date = date
        _period = State(initialValue: period)
        _periodStart = State(initialValue: period.start(for: date))
    }

    private var current: [PeriodGoal] { PlannerRules.goals(goals, period: period, containing: periodStart) }
    private var previousUnfinished: [PeriodGoal] {
        PlannerRules.goals(goals, period: period, containing: period.previous(before: periodStart))
            .filter { $0.status == .open }
    }
    private var parentGoals: [PeriodGoal] {
        guard let parent = period.parent else { return [] }
        return PlannerRules.goals(goals, period: parent, containing: periodStart)
    }

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(GoalPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, p in periodStart = p.start(for: date) }

                HStack {
                    Button { periodStart = period.previous(before: periodStart) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    VStack {
                        Text(period.label(for: periodStart)).font(.headline)
                        Text("\(current.filter(\.isDone).count) / \(current.count) done").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { periodStart = period.next(after: periodStart) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            }

            if !previousUnfinished.isEmpty {
                Section {
                    Button("Carry over \(previousUnfinished.count) unfinished goal\(previousUnfinished.count == 1 ? "" : "s")") {
                        carryOver()
                    }
                    Button("Close them as not done", role: .destructive) {
                        previousUnfinished.forEach { $0.status = .notDone }
                        try? modelContext.save()
                    }
                } header: {
                    Text("From last \(period.title.lowercased())")
                } footer: {
                    Text(previousUnfinished.map(\.title).joined(separator: " · "))
                }
            }

            Section("Goals") {
                ForEach(current) { goal in
                    PeriodGoalRow(goal: goal, parents: parentGoals, children: goals.filter { $0.parentGoalID == goal.id })
                }
                .onDelete { offsets in
                    offsets.map { current[$0] }.forEach(modelContext.delete)
                    try? modelContext.save()
                }
                ForEach(0..<max(0, 3 - current.count), id: \.self) { _ in
                    Text("Empty slot").foregroundStyle(.tertiary)
                }
                HStack {
                    TextField("Add a goal", text: $newTitle)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newTitle.trimmed.isEmpty)
                }
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func add() {
        let title = newTitle.trimmed
        guard !title.isEmpty else { return }
        modelContext.insert(PeriodGoal(title: title, period: period, periodStart: periodStart, sortOrder: current.count))
        newTitle = ""
        try? modelContext.save()
    }

    private func carryOver() {
        var order = current.count
        for goal in previousUnfinished {
            modelContext.insert(PeriodGoal(title: goal.title, period: period, periodStart: periodStart,
                                           sortOrder: order, parentGoalID: goal.parentGoalID))
            goal.status = .carried
            order += 1
        }
        try? modelContext.save()
    }
}

private struct PeriodGoalRow: View {
    @Bindable var goal: PeriodGoal
    let parents: [PeriodGoal]
    let children: [PeriodGoal]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                GoalTickRow(goal: goal)
                Menu {
                    Button("Open") { goal.status = .open }
                    Button("Done") { goal.status = .done }
                    Button("Not done") { goal.status = .notDone }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
            }
            if let parentPeriod = goal.period.parent {
                Picker("Serves", selection: $goal.parentGoalID) {
                    Text("No \(parentPeriod.title.lowercased()) goal").tag(UUID?.none)
                    ForEach(parents) { Text($0.title).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .disabled(parents.isEmpty)
            }
            if !children.isEmpty {
                Text("\(children.filter(\.isDone).count) / \(children.count) linked goals done")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: goal.statusRaw) { _, _ in try? modelContext.save() }
        .onChange(of: goal.parentGoalID) { _, _ in try? modelContext.save() }
    }
}
