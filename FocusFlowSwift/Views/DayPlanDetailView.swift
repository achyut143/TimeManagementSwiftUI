import SwiftUI
import SwiftData

/// Everything for one day in one place. Opened from the status strip; opens
/// straight into edit mode while the day is still "Pending". Edits are held
/// in drafts and only written on Save.
struct DayPlanDetailView: View {
    let date: Date
    @State private var isEditing: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var days: [PlannerDay]
    @Query private var goals: [PeriodGoal]
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @Query private var budgets: [ImpulseBudgetVersion]
    @Query private var schedules: [SleepScheduleVersion]
    @Query(filter: #Predicate<Task> { $0.impulseTypeID != nil }) private var impulseTasks: [Task]
    @Query(sort: \IfThenPlan.sortOrder) private var ifThenPlans: [IfThenPlan]
    @Query private var foodEntries: [FoodEntry]
    @Query private var foodBreaks: [FoodBreak]

    @State private var draft = Draft()
    @State private var showFoodPlan = false

    init(date: Date, startInEdit: Bool) {
        self.date = date.startOfDay
        _isEditing = State(initialValue: startInEdit)
    }

    private var planner: PlannerDay? { days.first { $0.date == date } }
    private var status: PlannerDayStatus {
        PlannerRules.dayStatus(for: date, days: days, goals: goals, impulseTasks: impulseTasks, food: foodEntries)
    }
    private var activeTypes: [ImpulseType] { types.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            Form {
                if isEditing { editSections } else { readSections }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if status.isPlanned { isEditing = false; loadDraft() } else { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save(); isEditing = false }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { loadDraft(); isEditing = true }
                    }
                }
            }
            .onAppear(perform: loadDraft)
            .sheet(isPresented: $showFoodPlan) {
                NavigationStack { FoodPlanEditorView(date: date) }
            }
        }
    }

    // MARK: - Read mode

    @ViewBuilder
    private var readSections: some View {
        Section {
            HStack {
                Text("Day plan")
                Spacer()
                Badge(text: status.isPlanned ? "Planned" : "Pending", color: status.isPlanned ? .green : .orange)
            }
        }

        Section("Wake-up and sleep") {
            if let v = PlannerRules.activeSchedule(on: date, versions: schedules) {
                readSleepRow("Wake", target: PlannerRules.wakeTarget(on: date, v), actual: planner?.wakeActual,
                             mark: PlannerRules.wakeMark(planner, on: date, versions: schedules))
                readSleepRow("Sleep", target: PlannerRules.sleepTarget(on: date, v), actual: planner?.sleepActual,
                             mark: PlannerRules.sleepMark(planner, on: date, versions: schedules))
            } else {
                Text("No sleep schedule set — add one in Planner Settings.").foregroundStyle(.secondary)
            }
        }

        Section("Goals \(status.dayGoals.filter(\.isDone).count) / \(status.dayGoals.count)") {
            if status.dayGoals.isEmpty { Text("No goals yet").foregroundStyle(.secondary) }
            ForEach(status.dayGoals) { goal in
                VStack(alignment: .leading, spacing: 2) {
                    GoalTickRow(goal: goal)
                    if let parent = goals.first(where: { $0.id == goal.parentGoalID }) {
                        Label(parent.title, systemImage: "arrow.turn.left.up")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach([GoalPeriod.week, .month, .quarter]) { period in
                let list = PlannerRules.goals(goals, period: period, containing: date)
                HStack {
                    Text(period.label(for: period.start(for: date))).font(.caption)
                    Spacer()
                    Text("\(list.filter(\.isDone).count) / \(list.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        foodSection

        Section("Workout") {
            if planner?.restDay == true {
                Badge(text: "Rest day", color: .teal)
            } else if let planner, planner.workoutPlanned {
                HStack {
                    Text(planner.workout)
                    Spacer()
                    if let time = planner.workoutTime {
                        Text(time.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    if planner.workoutDone { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            } else {
                Text("Not planned").foregroundStyle(.secondary)
            }
        }

        Section("Impulses") {
            if status.noImpulseBroken {
                Badge(text: "No-impulse day broken", color: .red)
            } else if status.noImpulseDay {
                Badge(text: "No-impulse day", color: .green)
            }
            if status.impulseTasks.isEmpty && !status.noImpulseDay {
                Text("Nothing scheduled").foregroundStyle(.secondary)
            }
            ForEach(status.impulseTasks) { task in
                ImpulseTaskRow(task: task, type: types.first { $0.id == task.impulseTypeID }, noImpulseDay: status.noImpulseDay)
            }
        }

        let budget = ImpulseRules.budget(forMonthOf: date, tasks: impulseTasks, versions: budgets)
        if budget.budgetMinutes != nil {
            Section {
                ImpulseBudgetBar(summary: budget, types: types)
            }
        }

        Section("If-then plans") {
            ForEach(ifThenPlans.filter { !$0.trigger.trimmed.isEmpty }) { IfThenSummaryRow(plan: $0) }
            NavigationLink("Edit if-then plans") { IfThenPlansView() }
        }
    }

    private func readSleepRow(_ label: String, target: Date, actual: Date?, mark: SleepMark?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(target.formatted(date: .omitted, time: .shortened)) → \(actual?.formatted(date: .omitted, time: .shortened) ?? "—")")
                .foregroundStyle(.secondary)
            if let mark { MarkPill(mark: mark) }
        }
    }

    /// The day's food breaks from the Food module (read-only here; edited in the food plan).
    private var foodSection: some View {
        Section {
            ForEach(FoodRules.slots(on: date, entries: foodEntries, breaks: foodBreaks)) { slot in
                HStack {
                    Image(systemName: slot.icon).foregroundStyle(.teal).frame(width: 20)
                    Text(slot.name)
                    Spacer()
                    Text(slot.food.isEmpty ? "Not planned" : slot.food).foregroundStyle(.secondary).lineLimit(1)
                    Text(slot.time.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if slot.status == .eaten { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    if slot.status == .swapped { Image(systemName: "arrow.triangle.swap").foregroundStyle(.red) }
                }
            }
            let unplanned = FoodRules.entries(on: date, foodEntries).filter(\.isUnplanned)
            if !unplanned.isEmpty {
                Label("\(unplanned.count) unplanned", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
            Button { showFoodPlan = true } label: { Label("Plan food", systemImage: "square.and.pencil") }
        } header: {
            Text("Food")
        }
    }

    // MARK: - Edit mode

    @ViewBuilder
    private var editSections: some View {
        if !status.isPlanned {
            Section {
                checklistRow("3 or more goals", done: draft.goals.filter { !$0.title.trimmed.isEmpty }.count >= 3)
                checklistRow("Food planned for every break", done: status.mealsDone)
                checklistRow("Workout or rest day", done: draft.restDay || !draft.workout.trimmed.isEmpty)
                checklistRow("Impulse time or no-impulse day", done: draft.noImpulseDay || draft.impulses.contains { !$0.deleted })
            } header: {
                Text("To finish planning")
            }
        }

        Section("Goals") {
            ForEach($draft.goals) { $goal in
                HStack {
                    Button {
                        goal.done.toggle()
                    } label: {
                        Image(systemName: goal.done ? "checkmark.square.fill" : "square")
                            .foregroundStyle(goal.done ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading) {
                        TextField("Goal", text: $goal.title)
                        let weekGoals = PlannerRules.goals(goals, period: .week, containing: date)
                        if !weekGoals.isEmpty {
                            Picker("Serves", selection: $goal.parentID) {
                                Text("No week goal").tag(UUID?.none)
                                ForEach(weekGoals) { Text($0.title).tag(Optional($0.id)) }
                            }
                            .font(.caption)
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
            .onDelete { draft.goals.remove(atOffsets: $0) }
            Button {
                draft.goals.append(GoalDraft())
            } label: {
                Label("Add goal", systemImage: "plus")
            }
        }

        foodSection

        Section("Workout") {
            Toggle("Rest day", isOn: $draft.restDay)
            if !draft.restDay {
                TextField("e.g. Gym — legs, 5 km run", text: $draft.workout)
                Toggle("Set a time", isOn: $draft.hasWorkoutTime)
                if draft.hasWorkoutTime {
                    DatePicker("Time", selection: $draft.workoutTime, displayedComponents: .hourAndMinute)
                }
                Toggle("Done", isOn: $draft.workoutDone)
            }
        }

        Section {
            Toggle("No-impulse day", isOn: $draft.noImpulseDay)
            ForEach($draft.impulses) { $item in
                if !item.deleted { impulseEditor($item) }
            }
            if activeTypes.isEmpty {
                Text("Create an impulse type in Planner Settings first.").font(.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    draft.impulses.append(ImpulseDraft(type: activeTypes[0], day: date))
                } label: {
                    Label("Add impulse time", systemImage: "plus")
                }
            }
        } header: {
            Text("Impulses")
        } footer: {
            Text("New or moved impulse time is checked against each type's plan-before time when you save. Time logged after it started is always unplanned.")
        }

        Section("Actual wake-up and sleep") {
            Toggle("Woke up", isOn: $draft.hasWake)
            if draft.hasWake { DatePicker("At", selection: $draft.wake, displayedComponents: .hourAndMinute) }
            Toggle("Went to sleep", isOn: $draft.hasSleep)
            if draft.hasSleep {
                DatePicker("At", selection: $draft.sleep, displayedComponents: .hourAndMinute)
                Text("Times before noon count as after midnight that night.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func checklistRow(_ text: String, done: Bool) -> some View {
        Label(text, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
    }

    private func impulseEditor(_ item: Binding<ImpulseDraft>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Type", selection: item.typeID) {
                    ForEach(types.filter { !$0.isArchived || $0.id == item.wrappedValue.typeID }) { type in
                        Text(type.name).tag(type.id)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button(role: .destructive) {
                    item.wrappedValue.deleted = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField("Title (optional)", text: item.title)
            DatePicker("Start", selection: item.start, displayedComponents: .hourAndMinute)
            if let warning = ImpulseRules.unplannedWarning(
                existing: item.wrappedValue.existing,
                typeID: item.wrappedValue.typeID,
                start: ImpulseRules.combine(day: date, time: item.wrappedValue.start),
                types: types,
                noImpulseDay: draft.noImpulseDay
            ) {
                UnplannedImpulseWarning(text: warning)
            }
            Stepper("Duration \(item.wrappedValue.duration) min", value: item.duration, in: 5...600, step: 5)
            Toggle("Ran longer", isOn: item.hasActualEnd)
            if item.wrappedValue.hasActualEnd {
                DatePicker("Actually ended", selection: item.actualEnd, displayedComponents: .hourAndMinute)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Draft

    private func loadDraft() {
        var d = Draft()
        d.goals = status.dayGoals.map { GoalDraft(existing: $0) }
        while d.goals.count < 3 { d.goals.append(GoalDraft()) }
        let p = planner
        d.noImpulseDay = p?.noImpulseDay ?? false
        d.restDay = p?.restDay ?? false
        d.workout = p?.workout ?? ""
        d.hasWorkoutTime = p?.workoutTime != nil
        d.workoutTime = p?.workoutTime ?? Calendar.current.date(byAdding: .hour, value: 7, to: date)!
        d.workoutDone = p?.workoutDone ?? false
        d.impulses = status.impulseTasks.map { ImpulseDraft(task: $0, day: date) }
        d.hasWake = p?.wakeActual != nil
        d.wake = p?.wakeActual ?? Calendar.current.date(byAdding: .hour, value: 7, to: date)!
        d.hasSleep = p?.sleepActual != nil
        d.sleep = p?.sleepActual ?? Calendar.current.date(byAdding: .hour, value: 22, to: date)!
        draft = d
    }

    private func save() {
        let p = PlannerDay.getOrCreate(for: date, context: modelContext)
        let cal = Calendar.current

        // Goals
        let keptIDs = Set(draft.goals.compactMap { $0.existing?.id })
        for goal in status.dayGoals where !keptIDs.contains(goal.id) { modelContext.delete(goal) }
        for (index, g) in draft.goals.enumerated() {
            let title = g.title.trimmed
            if let existing = g.existing {
                if title.isEmpty { modelContext.delete(existing); continue }
                existing.title = title
                existing.status = g.done ? .done : (existing.status == .done ? .open : existing.status)
                existing.parentGoalID = g.parentID
                existing.sortOrder = index
            } else if !title.isEmpty {
                let goal = PeriodGoal(title: title, period: .day, periodStart: date, sortOrder: index, parentGoalID: g.parentID)
                if g.done { goal.status = .done }
                modelContext.insert(goal)
            }
        }

        // Meals live in the Food module now (saved from its plan editor).

        p.noImpulseDay = draft.noImpulseDay

        // A rest day keeps whatever workout text was typed, but it isn't the plan.
        p.restDay = draft.restDay
        p.workout = draft.workout.trimmed
        p.workoutTime = draft.hasWorkoutTime ? place(draft.workoutTime, on: date) : nil
        p.workoutDone = !draft.restDay && draft.workoutDone && !p.workout.isEmpty

        // Wake & sleep: times are picked as clock times and placed on this day
        // (sleep before noon goes on the next calendar date).
        p.wakeActual = draft.hasWake ? place(draft.wake, on: date) : nil
        if draft.hasSleep {
            let placed = place(draft.sleep, on: date)
            p.sleepActual = cal.component(.hour, from: placed) < 12 ? cal.date(byAdding: .day, value: 1, to: placed) : placed
        } else {
            p.sleepActual = nil
        }

        // Impulse tasks
        for item in draft.impulses {
            if item.deleted {
                if let task = item.existing { modelContext.delete(task) }
                continue
            }
            let task: Task
            let before: ImpulseRules.Snapshot?
            if let existing = item.existing {
                task = existing
                before = ImpulseRules.Snapshot(existing)
            } else {
                task = Task(weight: 0, date: date)
                modelContext.insert(task)
                before = nil
            }
            let typeName = types.first { $0.id == item.typeID }?.name ?? "Impulse"
            task.title = item.title.trimmed.isEmpty ? typeName : item.title.trimmed
            task.impulseTypeID = item.typeID
            task.date = date
            let start = place(item.start, on: date)
            let end = cal.date(byAdding: .minute, value: item.duration, to: start)!
            task.startTime = Self.hm(start)
            task.endTime = Self.hm(end)
            let actual = place(item.actualEnd, on: date)
            task.actualEndTime = item.hasActualEnd && actual > end ? Self.hm(actual) : nil
            ImpulseRules.reconcile(task, before: before, types: types)
        }

        try? modelContext.save()
        NotificationCenter.default.post(name: NSNotification.Name("TaskUpdated"), object: nil)
    }

    private func place(_ time: Date, on day: Date) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: time)
        return cal.date(byAdding: DateComponents(hour: c.hour, minute: c.minute), to: day.startOfDay)!
    }

    static func hm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

// MARK: - Draft types

private struct Draft {
    var goals: [GoalDraft] = []
    var noImpulseDay = false
    var restDay = false
    var workout = ""
    var hasWorkoutTime = false
    var workoutTime = Date()
    var workoutDone = false
    var impulses: [ImpulseDraft] = []
    var hasWake = false
    var wake = Date()
    var hasSleep = false
    var sleep = Date()
}

private struct GoalDraft: Identifiable {
    let id = UUID()
    var existing: PeriodGoal?
    var title = ""
    var done = false
    var parentID: UUID?

    init() {}

    init(existing: PeriodGoal) {
        self.existing = existing
        title = existing.title
        done = existing.isDone
        parentID = existing.parentGoalID
    }
}

private struct ImpulseDraft: Identifiable {
    let id = UUID()
    var existing: Task?
    var typeID: UUID
    var title = ""
    var start: Date
    var duration: Int
    var hasActualEnd = false
    var actualEnd: Date
    var deleted = false

    init(type: ImpulseType, day: Date) {
        typeID = type.id
        start = Calendar.current.date(byAdding: .hour, value: 20, to: day)!
        duration = 30
        actualEnd = start.addingTimeInterval(30 * 60)
    }

    init(task: Task, day: Date) {
        existing = task
        typeID = task.impulseTypeID ?? UUID()
        title = task.title
        start = ImpulseRules.startDate(of: task) ?? Calendar.current.date(byAdding: .hour, value: 20, to: day)!
        duration = max(5, Int(ImpulseRules.scheduledMinutes(of: task)))
        hasActualEnd = task.actualEndTime != nil
        if let actual = task.actualEndTime, let mins = ImpulseRules.minutes(from: actual) {
            actualEnd = Calendar.current.date(byAdding: .minute, value: mins, to: day)!
        } else {
            actualEnd = start.addingTimeInterval(Double(duration) * 60)
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
