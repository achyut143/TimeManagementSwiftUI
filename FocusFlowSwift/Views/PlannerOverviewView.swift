import SwiftUI
import SwiftData

/// Day overview card + status strip, shown above the task calendar for the
/// selected date.
struct PlannerHeaderView: View {
    let date: Date
    @Environment(\.modelContext) private var modelContext
    @Query private var days: [PlannerDay]
    @Query private var goals: [PeriodGoal]
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @Query private var budgets: [ImpulseBudgetVersion]
    @Query private var schedules: [SleepScheduleVersion]
    @Query(filter: #Predicate<Task> { $0.impulseTypeID != nil }) private var impulseTasks: [Task]
    @Query(sort: \IfThenPlan.sortOrder) private var ifThenPlans: [IfThenPlan]

    // Collapsed by default so the pinned header leaves room for the calendar.
    @AppStorage("plannerOverviewExpanded") private var overviewExpanded = false
    @State private var showDayPlan = false
    @State private var dayPlanInEdit = false
    @State private var showGoals = false
    @State private var showSettings = false
    @State private var showIfThen = false

    private var day: Date { date.startOfDay }
    private var planner: PlannerDay? { days.first { $0.date == day } }
    private var status: PlannerDayStatus {
        PlannerRules.dayStatus(for: day, days: days, goals: goals, impulseTasks: impulseTasks)
    }
    private var budget: BudgetSummary {
        ImpulseRules.budget(forMonthOf: day, tasks: impulseTasks, versions: budgets)
    }

    var body: some View {
        VStack(spacing: 8) {
            overviewCard
            statusStrip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showDayPlan) {
            DayPlanDetailView(date: day, startInEdit: dayPlanInEdit)
        }
        .sheet(isPresented: $showGoals) {
            NavigationStack { PeriodGoalsView(date: day) }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { PlannerSettingsView() }
        }
        .sheet(isPresented: $showIfThen) {
            IfThenPlansSheet()
        }
    }

    // MARK: Overview

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { overviewExpanded.toggle() }
            } label: {
                HStack {
                    Text("Day overview")
                        .font(.subheadline.weight(.semibold))
                    Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: overviewExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if overviewExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        sleepSection
                        Divider()
                        goalsSection
                        Divider()
                        mealsSection
                        Divider()
                        impulsesSection
                        if budget.budgetMinutes != nil {
                            Divider()
                            ImpulseBudgetBar(summary: budget, types: types)
                        }
                        Divider()
                        ifThenSection
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let version = PlannerRules.activeSchedule(on: day, versions: schedules) {
                sleepRow(icon: "sun.horizon.fill", label: "Wake",
                         target: PlannerRules.wakeTarget(on: day, version),
                         actual: planner?.wakeActual,
                         mark: PlannerRules.wakeMark(planner, on: day, versions: schedules))
                sleepRow(icon: "moon.zzz.fill", label: "Sleep",
                         target: PlannerRules.sleepTarget(on: day, version),
                         actual: planner?.sleepActual,
                         mark: PlannerRules.sleepMark(planner, on: day, versions: schedules))
                if day == Date().startOfDay {
                    HStack {
                        Button("I'm up") { recordWake() }
                        Button("Going to sleep") { recordSleep() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button {
                    showSettings = true
                } label: {
                    Label("Set your wake-up and sleep times", systemImage: "bed.double")
                        .font(.caption)
                }
            }
        }
    }

    private func sleepRow(icon: String, label: String, target: Date, actual: Date?, mark: SleepMark?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.indigo).frame(width: 18)
            Text(label).font(.caption.weight(.medium)).frame(width: 40, alignment: .leading)
            Text(target.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(actual?.formatted(date: .omitted, time: .shortened) ?? "—").font(.caption)
            Spacer()
            if let mark { MarkPill(mark: mark) }
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Goals").font(.caption.weight(.semibold))
                Spacer()
                Text("\(status.dayGoals.filter(\.isDone).count) / \(status.dayGoals.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(status.dayGoals) { goal in
                GoalTickRow(goal: goal)
            }
            ForEach(0..<max(0, 3 - status.dayGoals.count), id: \.self) { _ in
                Button {
                    openDayPlan(edit: true)
                } label: {
                    HStack {
                        Image(systemName: "circle.dashed")
                        Text("Add a goal")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            DisclosureGroup {
                ForEach([GoalPeriod.week, .month, .quarter]) { period in
                    let periodGoals = PlannerRules.goals(goals, period: period, containing: day)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(period.label(for: period.start(for: day))).font(.caption.weight(.medium))
                            Spacer()
                            Text("\(periodGoals.filter(\.isDone).count) / \(periodGoals.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if periodGoals.isEmpty {
                            Button("Set this \(period.title.lowercased())'s goals") { showGoals = true }
                                .font(.caption)
                        }
                        ForEach(periodGoals) { GoalTickRow(goal: $0) }
                    }
                    .padding(.top, 4)
                }
            } label: {
                Text("Week, month and quarter").font(.caption).foregroundStyle(.secondary)
            }

            if let prompt = periodPrompt {
                Button {
                    showGoals = true
                } label: {
                    Label(prompt, systemImage: "flag.fill")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.indigo.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
            }
        }
    }

    /// Shown when a new week, month or quarter has started without goals.
    private var periodPrompt: String? {
        let missing = [GoalPeriod.week, .month, .quarter].filter {
            PlannerRules.goals(goals, period: $0, containing: day).isEmpty
        }
        guard !missing.isEmpty else { return nil }
        return "Set goals for this " + missing.map { $0.title.lowercased() }.joined(separator: ", ")
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meals").font(.caption.weight(.semibold))
            mealRow("Breakfast", text: planner?.breakfast, time: planner?.breakfastTime, eaten: planner?.breakfastEaten ?? false) { planner?.breakfastEaten.toggle() }
            mealRow("Lunch", text: planner?.lunch, time: planner?.lunchTime, eaten: planner?.lunchEaten ?? false) { planner?.lunchEaten.toggle() }
            mealRow("Dinner", text: planner?.dinner, time: planner?.dinnerTime, eaten: planner?.dinnerEaten ?? false) { planner?.dinnerEaten.toggle() }
        }
    }

    private func mealRow(_ name: String, text: String?, time: Date?, eaten: Bool, toggle: @escaping () -> Void) -> some View {
        let planned = !(text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: 6) {
            Button {
                toggle()
                try? modelContext.save()
            } label: {
                Image(systemName: eaten ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(eaten ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!planned)
            Text(name).font(.caption.weight(.medium)).frame(width: 64, alignment: .leading)
            Text(planned ? text! : "Not planned")
                .font(.caption)
                .foregroundStyle(planned ? .primary : .secondary)
                .lineLimit(1)
            Spacer()
            if let time { Text(time.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private var impulsesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Impulses").font(.caption.weight(.semibold))
                Spacer()
                if status.noImpulseBroken {
                    Badge(text: "No-impulse day broken", color: .red)
                } else if status.noImpulseDay {
                    Badge(text: "No-impulse day", color: .green)
                }
            }
            if status.impulseTasks.isEmpty && !status.noImpulseDay {
                Text("No impulse time planned").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(status.impulseTasks.sorted { (ImpulseRules.startDate(of: $0) ?? .distantFuture) < (ImpulseRules.startDate(of: $1) ?? .distantFuture) }) { task in
                ImpulseTaskRow(task: task, type: types.first { $0.id == task.impulseTypeID }, noImpulseDay: status.noImpulseDay)
            }
        }
    }

    private var ifThenSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("If-then plans").font(.caption.weight(.semibold))
                Spacer()
                Button("Edit") { showIfThen = true }.font(.caption)
            }
            let filled = ifThenPlans.filter { !$0.trigger.trimmed.isEmpty }
            if filled.isEmpty {
                Text("Decide now how you'll respond when you're tempted").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(filled) { IfThenSummaryRow(plan: $0) }
        }
    }

    // MARK: Status strip

    private var statusStrip: some View {
        Button {
            openDayPlan(edit: !status.isPlanned)
        } label: {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    StripChip(title: "Day plan", value: status.isPlanned ? "Planned" : "Pending",
                              color: status.isPlanned ? .green : .orange)
                    StripChip(title: "Goals",
                              value: "\(status.dayGoals.filter(\.isDone).count) / \(status.dayGoals.count)",
                              color: status.goalsDone ? .indigo : .secondary)
                    StripChip(title: "Meals",
                              value: status.mealsPlanned == 0 ? "?" : "\(status.mealsPlanned) / 3",
                              color: status.mealsDone ? .teal : .secondary)
                    StripChip(title: "Impulse", value: impulseChipText, color: impulseChipColor)
                    StripChip(title: "Sleep", value: sleepChipText, color: .indigo)
                    if let budgetMinutes = budget.budgetMinutes {
                        StripChip(title: "Budget",
                                  value: "\(PlannerRules.formatHours(budget.usedMinutes)) / \(PlannerRules.formatHours(budgetMinutes)) h",
                                  color: budget.state.color)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var impulseChipText: String {
        if status.noImpulseBroken { return "No-impulse broken" }
        if status.noImpulseDay { return "No-impulse day" }
        if status.impulseTasks.isEmpty { return "?" }
        return "\(PlannerRules.formatMinutes(status.plannedImpulseMinutes)) planned"
    }

    private var impulseChipColor: Color {
        if status.noImpulseBroken { return .red }
        if status.noImpulseDay { return .green }
        return status.impulseTasks.isEmpty ? .secondary : .pink
    }

    private var sleepChipText: String {
        let wake = PlannerRules.wakeMark(planner, on: day, versions: schedules)
        let sleep = PlannerRules.sleepMark(planner, on: day, versions: schedules)
        guard wake != nil || sleep != nil else { return "?" }
        return "↑ \(wake?.text ?? "?")  ↓ \(sleep?.text ?? "?")"
    }

    // MARK: Actions

    private func openDayPlan(edit: Bool) {
        dayPlanInEdit = edit
        showDayPlan = true
    }

    private func recordWake() {
        PlannerDay.getOrCreate(for: Date(), context: modelContext).wakeActual = Date()
        try? modelContext.save()
    }

    private func recordSleep() {
        let now = Date()
        PlannerDay.getOrCreate(for: PlannerRules.sleepDay(for: now), context: modelContext).sleepActual = now
        try? modelContext.save()
    }
}

// MARK: - Shared pieces

struct IfThenSummaryRow: View {
    let plan: IfThenPlan

    var body: some View {
        (Text("If ").bold().foregroundColor(.orange) + Text(plan.trigger)
         + Text(" → ").foregroundColor(.secondary)
         + Text(plan.response.isEmpty ? "…" : plan.response))
            .font(.caption)
    }
}

/// The if-then editor (from PlanDetailViews) presented on its own.
struct IfThenPlansSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            IfThenPlansView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

struct StripChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct MarkPill: View {
    let mark: SleepMark
    var body: some View { Badge(text: mark.text, color: mark.color) }
}

struct GoalTickRow: View {
    @Bindable var goal: PeriodGoal
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button {
            goal.status = goal.isDone ? .open : .done
            try? modelContext.save()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: goal.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(goal.isDone ? .green : .secondary)
                Text(goal.title)
                    .font(.caption)
                    .strikethrough(goal.isDone)
                    .foregroundStyle(goal.status == .notDone ? .secondary : .primary)
                    .lineLimit(2)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ImpulseTaskRow: View {
    let task: Task
    let type: ImpulseType?
    let noImpulseDay: Bool

    var body: some View {
        let planned = ImpulseRules.isPlannedLabel(task, noImpulseDay: noImpulseDay)
        let overrun = planned ? ImpulseRules.unplannedMinutes(of: task, noImpulseDay: noImpulseDay) : 0
        HStack(spacing: 6) {
            Circle().fill(type?.color ?? .gray).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title.isEmpty ? (type?.name ?? "Impulse") : task.title)
                    .font(.caption)
                    .strikethrough(ImpulseRules.isSkipped(task))
                Text(timeText).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if overrun > 0 {
                Text("+\(PlannerRules.formatMinutes(overrun)) unplanned").font(.caption2).foregroundStyle(.red)
            }
            Badge(text: planned ? "Planned" : "Unplanned", color: planned ? .green : .red)
        }
    }

    private var timeText: String {
        let minutes = ImpulseRules.actualMinutes(of: task)
        guard !task.startTime.isEmpty else { return PlannerRules.formatMinutes(minutes) }
        let end = task.actualEndTime ?? task.endTime
        return "\(formatTimeToAMPM(task.startTime)) – \(formatTimeToAMPM(end)) · \(PlannerRules.formatMinutes(minutes))"
    }
}

struct ImpulseBudgetBar: View {
    let summary: BudgetSummary
    let types: [ImpulseType]

    var body: some View {
        let budget = summary.budgetMinutes ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Monthly budget").font(.caption.weight(.semibold))
                Badge(text: summary.state.text, color: summary.state.color)
                Spacer()
                Text("\(PlannerRules.formatHours(summary.usedMinutes)) of \(PlannerRules.formatHours(budget)) h used")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let scale = max(budget, summary.usedMinutes + summary.committedMinutes, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    HStack(spacing: 0) {
                        Rectangle().fill(summary.state.color)
                            .frame(width: geo.size.width * summary.usedMinutes / scale)
                        Rectangle().fill(summary.state.color.opacity(0.35))
                            .frame(width: geo.size.width * summary.committedMinutes / scale)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 8)
            HStack(spacing: 10) {
                Text("Committed \(PlannerRules.formatMinutes(summary.committedMinutes))")
                Text("Remaining \(PlannerRules.formatMinutes(summary.remainingMinutes))")
            }
            .font(.caption2).foregroundStyle(.secondary)
            if !summary.byType.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(summary.byType.sorted { $0.value > $1.value }, id: \.key) { id, minutes in
                        let type = types.first { $0.id == id }
                        HStack(spacing: 3) {
                            Circle().fill(type?.color ?? .gray).frame(width: 6, height: 6)
                            Text("\(type?.name ?? "Deleted") \(PlannerRules.formatMinutes(minutes))")
                        }
                        .font(.caption2)
                    }
                }
            }
        }
    }
}

/// Diagonal stripes used to mark unplanned impulse tasks on the calendar.
struct StripeFill: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}
