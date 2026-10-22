import SwiftUI
import SwiftData
import Charts

/// Planned vs unplanned impulse time, budget, and whether plans and routines hold.
struct PlannerMetricsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var days: [PlannerDay]
    @Query private var goals: [PeriodGoal]
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @Query private var budgets: [ImpulseBudgetVersion]
    @Query(sort: \SleepScheduleVersion.effectiveFrom, order: .reverse) private var schedules: [SleepScheduleVersion]
    @Query(filter: #Predicate<Task> { $0.impulseTypeID != nil }) private var impulseTasks: [Task]

    @State private var month = ImpulseRules.monthStart(for: Date())

    private let cal = Calendar.current
    private var today: Date { Date().startOfDay }
    private var monthEnd: Date { GoalPeriod.month.next(after: month) }

    /// Days of the selected month up to today.
    private var elapsedDays: [Date] {
        var result: [Date] = []
        var d = month
        while d < monthEnd && d <= today {
            result.append(d)
            d = PlanDates.adding(1, to: d)
        }
        return result
    }

    private var noImpulseDays: Set<Date> { Set(days.filter(\.noImpulseDay).map(\.date)) }

    private func split(_ tasks: [Task]) -> ImpulseRules.Split {
        ImpulseRules.split(tasks, noImpulseDays: noImpulseDays)
    }

    private func percent(_ part: Double, of whole: Double) -> String {
        whole > 0 ? "\(Int((part / whole * 100).rounded()))%" : "–"
    }

    var body: some View {
        let monthTasks = ImpulseRules.tasks(impulseTasks, inMonthOf: month)
        let totals = split(monthTasks)
        List {
            Section {
                HStack {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right") }
                        .disabled(month >= ImpulseRules.monthStart(for: Date()))
                }
                .buttonStyle(.borderless)
            }

            Section("Planned vs unplanned impulse") {
                metric("Planned", "\(PlannerRules.formatMinutes(totals.planned)) · \(totals.plannedCount) tasks")
                metric("Unplanned", "\(PlannerRules.formatMinutes(totals.unplanned)) · \(totals.unplannedCount) tasks")
                metric("Planned share", percent(totals.planned, of: totals.planned + totals.unplanned))
                ForEach(types) { type in
                    let s = split(monthTasks.filter { $0.impulseTypeID == type.id })
                    if s.planned + s.unplanned > 0 {
                        HStack {
                            Circle().fill(type.color).frame(width: 8, height: 8)
                            Text(type.name)
                            Spacer()
                            Text("\(PlannerRules.formatMinutes(s.planned)) planned, \(PlannerRules.formatMinutes(s.unplanned)) unplanned (\(percent(s.planned, of: s.planned + s.unplanned)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(weeksInMonth, id: \.self) { week in
                    let s = split(monthTasks.filter { t in t.date.map { PlanDates.weekStart(for: $0) == week } ?? false })
                    if s.planned + s.unplanned > 0 {
                        metric("Week of \(week.formatted(.dateTime.month(.abbreviated).day()))",
                               "\(PlannerRules.formatMinutes(s.planned)) / \(PlannerRules.formatMinutes(s.unplanned)) · \(percent(s.planned, of: s.planned + s.unplanned))")
                    }
                }
                NavigationLink {
                    ImpulseTrendView(anchor: min(today, cal.date(byAdding: .day, value: -1, to: monthEnd)!))
                } label: {
                    trendChart
                }
            }

            budgetSection(monthTasks: monthTasks)

            Section("No-impulse days") {
                let marked = elapsedDays.filter { noImpulseDays.contains($0) }
                let broken = marked.filter { d in
                    PlannerRules.dayStatus(for: d, days: days, goals: goals, impulseTasks: impulseTasks).noImpulseBroken
                }
                metric("This month", "\(marked.count) days, \(broken.count) broken")
            }

            Section("Goal completion") {
                ForEach(GoalPeriod.allCases) { period in
                    let list = PlannerRules.goals(goals, period: period, containing: Date())
                    metric("This \(period.title.lowercased())", "\(list.filter(\.isDone).count) / \(list.count)")
                }
            }

            Section("Days fully planned") {
                let planned = elapsedDays.filter { isPlanned($0) }
                metric("This month", "\(planned.count) of \(elapsedDays.count) days (\(percent(Double(planned.count), of: Double(elapsedDays.count))))")
                metric("Current streak", "\(streak) days")
            }

            Section("Wake-up and sleep") {
                if schedules.isEmpty {
                    Text("No sleep schedule set").foregroundStyle(.secondary)
                }
                ForEach(schedules) { v in sleepStats(for: v) }
            }

            Section("Workouts") {
                let records = elapsedDays.compactMap { d in days.first { $0.date == d } }
                let rest = records.filter(\.restDay).count
                let planned = records.filter { !$0.restDay && $0.workoutPlanned }
                let done = planned.filter(\.workoutDone).count
                metric("Done", "\(done) of \(planned.count) planned (\(percent(Double(done), of: Double(planned.count))))")
                metric("Rest days", "\(rest)")
                metric("Days with a workout or rest day", percent(Double(planned.count + rest), of: Double(elapsedDays.count)))
            }

            Section("Meals") {
                let full = elapsedDays.filter { d in (days.first { $0.date == d }?.mealsPlanned ?? 0) == 3 }
                metric("All 3 meals planned", "\(percent(Double(full.count), of: Double(elapsedDays.count))) of days")
            }
        }
        .navigationTitle("Planner Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private var weeksInMonth: [Date] {
        var weeks: [Date] = []
        var d = month
        while d < monthEnd {
            let w = PlanDates.weekStart(for: d)
            if !weeks.contains(w) { weeks.append(w) }
            d = PlanDates.adding(1, to: d)
        }
        return weeks
    }

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let month: Date
        let kind: String
        let hours: Double
    }

    private var trendChart: some View {
        let points: [TrendPoint] = (0..<6).reversed().flatMap { back -> [TrendPoint] in
            let m = cal.date(byAdding: .month, value: -back, to: month)!
            let s = split(ImpulseRules.tasks(impulseTasks, inMonthOf: m))
            return [TrendPoint(month: m, kind: "Planned", hours: s.planned / 60),
                    TrendPoint(month: m, kind: "Unplanned", hours: s.unplanned / 60)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last 6 months (hours)")
                Spacer()
                Text("Weekly · monthly · quarterly")
            }
            .font(.caption).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Month", p.month, unit: .month), y: .value("Hours", p.hours))
                    .foregroundStyle(by: .value("Kind", p.kind))
            }
            .chartForegroundStyleScale(["Planned": Color.green, "Unplanned": Color.red])
            // Label every month — the automatic axis skips every other one.
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .frame(height: 140)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func budgetSection(monthTasks: [Task]) -> some View {
        let summary = ImpulseRules.budget(forMonthOf: month, tasks: impulseTasks, versions: budgets)
        Section("Budget use") {
            if summary.budgetMinutes == nil {
                Text("No budget set for this month").foregroundStyle(.secondary)
            } else {
                ImpulseBudgetBar(summary: summary, types: types)
                let daysInMonth = Double(cal.range(of: .day, in: .month, for: month)?.count ?? 30)
                let elapsed = Double(elapsedDays.count)
                if month == ImpulseRules.monthStart(for: Date()), elapsed > 0 {
                    let projected = summary.usedMinutes / elapsed * daysInMonth
                    metric("On pace for", "\(PlannerRules.formatHours(max(projected, summary.usedMinutes + summary.committedMinutes))) h")
                }
            }
        }
    }

    private func isPlanned(_ day: Date) -> Bool {
        PlannerRules.dayStatus(for: day, days: days, goals: goals, impulseTasks: impulseTasks).isPlanned
    }

    /// Consecutive planned days ending today (or yesterday while today is still pending).
    private var streak: Int {
        var d = isPlanned(today) ? today : PlanDates.adding(-1, to: today)
        var count = 0
        while isPlanned(d) && count < 3650 {
            count += 1
            d = PlanDates.adding(-1, to: d)
        }
        return count
    }

    @ViewBuilder
    private func sleepStats(for v: SleepScheduleVersion) -> some View {
        let next = schedules.filter { $0.effectiveFrom > v.effectiveFrom }.map(\.effectiveFrom).min() ?? .distantFuture
        let range = stride(from: 0, to: 3650, by: 1).lazy
            .map { PlanDates.adding($0, to: v.effectiveFrom) }
            .prefix { $0 < next && $0 <= today }
        let marks = range.map { d -> (wake: SleepMark?, sleep: SleepMark?, wakeOff: Double?, sleepOff: Double?) in
            let p = days.first { $0.date == d }
            let wakeOff = p?.wakeActual.map { abs($0.timeIntervalSince(PlannerRules.wakeTarget(on: d, v))) / 60 }
            let sleepOff = p?.sleepActual.map { abs($0.timeIntervalSince(PlannerRules.sleepTarget(on: d, v))) / 60 }
            return (PlannerRules.mark(actual: p?.wakeActual, target: PlannerRules.wakeTarget(on: d, v), window: v.windowMinutes),
                    PlannerRules.mark(actual: p?.sleepActual, target: PlannerRules.sleepTarget(on: d, v), window: v.windowMinutes),
                    wakeOff, sleepOff)
        }
        let all = Array(marks)
        let wakeJudged = all.filter { $0.wake != .pending }
        let sleepJudged = all.filter { $0.sleep != .pending }
        let wakeOn = wakeJudged.filter { $0.wake == .onTime }.count
        let sleepOn = sleepJudged.filter { $0.sleep == .onTime }.count
        let wakeOffs = all.compactMap(\.wakeOff)
        let sleepOffs = all.compactMap(\.sleepOff)
        VStack(alignment: .leading, spacing: 4) {
            Text("\(v.label) since \(v.effectiveFrom.formatted(.dateTime.month(.abbreviated).day()))").font(.subheadline.weight(.medium))
            Text("Wake on time \(wakeOn) of \(wakeJudged.count) (\(percent(Double(wakeOn), of: Double(wakeJudged.count)))) · avg \(average(wakeOffs)) off")
                .font(.caption).foregroundStyle(.secondary)
            Text("Sleep on time \(sleepOn) of \(sleepJudged.count) nights (\(percent(Double(sleepOn), of: Double(sleepJudged.count)))) · avg \(average(sleepOffs)) off")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func average(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "–" }
        return PlannerRules.formatMinutes(values.reduce(0, +) / Double(values.count))
    }
}
