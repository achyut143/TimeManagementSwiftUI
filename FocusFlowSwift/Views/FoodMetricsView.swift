import SwiftUI
import SwiftData
import Charts

/// Cheats, plan-following, calories, money, cravings and triggers by week,
/// month or quarter.
struct FoodMetricsView: View {
    @Query private var entries: [FoodEntry]
    @Query private var cravings: [FoodCraving]
    @Query private var breaks: [FoodBreak]
    @AppStorage(FoodSettings.dailyCaloriesKey) private var dailyCalories = 2000
    @AppStorage(FoodSettings.weeklyBudgetKey) private var weeklyBudget = 0.0
    @AppStorage(FoodSettings.weeklyCheatsKey) private var weeklyCheats = 2

    @State private var period: GoalPeriod = .week
    @State private var back = 0
    @State private var calorieView: CalorieView = .day

    enum CalorieView: String, CaseIterable, Identifiable {
        case day = "Per day", week = "Per week"
        var id: String { rawValue }
    }

    /// One bar: calories from the plan and from cheats, stacked.
    private struct CalorieBar: Identifiable {
        let start: Date
        let kind: String
        let kcal: Double
        var id: String { "\(start.timeIntervalSince1970)-\(kind)" }
    }

    private func calorieBars(_ start: Date, _ end: Date) -> [CalorieBar] {
        let list = FoodRules.entries(entries, from: start, to: end)
        let cheat = list.filter { FoodRules.cheatReason($0) != nil }.reduce(0) { $0 + $1.eatenCalories }
        let total = list.reduce(0) { $0 + $1.eatenCalories }
        return [CalorieBar(start: start, kind: "Planned", kcal: total - cheat),
                CalorieBar(start: start, kind: "Cheats", kcal: cheat)]
    }

    private static let periods: [GoalPeriod] = [.week, .month, .quarter]

    private var windowStart: Date {
        var start = period.start(for: Date())
        for _ in 0..<back { start = period.previous(before: start) }
        return start
    }
    private var windowEnd: Date { period.next(after: windowStart) }
    private var inWindow: [FoodEntry] { FoodRules.entries(entries, from: windowStart, to: windowEnd) }

    /// Days in the window up to today.
    private var elapsedDays: [Date] {
        var days: [Date] = []
        var d = windowStart
        let end = min(windowEnd, Calendar.current.date(byAdding: .day, value: 1, to: Date().startOfDay)!)
        while d < end {
            days.append(d)
            d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
        }
        return days
    }

    /// Weeks in the window, for scaling the weekly budget and cheat allowance.
    private var weeksInWindow: Double { max(1, Double(elapsedDays.count) / 7) }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Self.periods) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in back = 0 }
                HStack {
                    Button { back += 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(period.label(for: windowStart)).font(.headline)
                    Spacer()
                    Button { back -= 1 } label: { Image(systemName: "chevron.right") }.disabled(back == 0)
                }
                .buttonStyle(.borderless)
            }

            cheatsSection
            chartSection
            planSection
            caloriesSection
            moneySection
            cravingsSection
            triggersSection
        }
        .navigationTitle("Food Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Cheats

    private var cheatsSection: some View {
        let cheats = FoodRules.cheats(inWindow)
        let previousStart = period.previous(before: windowStart)
        let previous = FoodRules.cheats(FoodRules.entries(entries, from: previousStart, to: windowStart)).count
        let allowance = Int((Double(weeklyCheats) * weeksInWindow).rounded())
        let reasons = Dictionary(grouping: cheats) { FoodRules.cheatReason($0)?.rawValue ?? "" }
        let start = FoodRules.trackingStart(breaks: breaks)
        let trackedDays = elapsedDays.filter { $0 >= start }
        let cleanDays = trackedDays.filter { FoodRules.isCleanDay($0, entries: entries, since: start) }.count

        return Section("Cheats") {
            HStack {
                Text("\(cheats.count)").font(.largeTitle.bold()).foregroundStyle(cheats.count > allowance ? .red : .green)
                VStack(alignment: .leading) {
                    Text("cheats (allowed \(allowance))").font(.subheadline)
                    let diff = cheats.count - previous
                    Text(diff == 0 ? "Same as last \(period.title.lowercased())" :
                            "\(abs(diff)) \(diff < 0 ? "fewer" : "more") than last \(period.title.lowercased())")
                        .font(.caption)
                        .foregroundStyle(diff <= 0 ? .green : .red)
                }
            }
            ForEach(reasons.keys.sorted(), id: \.self) { key in
                LabeledContent(key, value: "\(reasons[key]?.count ?? 0)")
            }
            LabeledContent("Clean days", value: "\(cleanDays) of \(trackedDays.count)")
            LabeledContent("Current clean streak", value: "\(FoodRules.cleanStreak(entries: entries, breaks: breaks)) days")
        }
    }

    /// Cheats per week (or month) for the last 8.
    private var chartSection: some View {
        let unit: GoalPeriod = period == .week ? .week : (period == .month ? .week : .month)
        var starts: [Date] = [unit.start(for: min(Date(), windowEnd.addingTimeInterval(-1)))]
        for _ in 0..<7 { starts.insert(unit.previous(before: starts[0]), at: 0) }
        let data = starts.map { s in
            (s, FoodRules.cheats(FoodRules.entries(entries, from: s, to: unit.next(after: s))).count)
        }
        return Section("Cheats per \(unit.title.lowercased())") {
            Chart(data, id: \.0) { item in
                BarMark(x: .value("Start", item.0, unit: unit == .week ? .weekOfYear : .month),
                        y: .value("Cheats", item.1))
                    .foregroundStyle(item.1 > (unit == .week ? weeklyCheats : weeklyCheats * 4) ? Color.red : Color.orange)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 160)
        }
    }

    // MARK: Plan

    private var planSection: some View {
        let planned = inWindow.filter { $0.kind == .planned && $0.hasPlan }
        let resolved = planned.filter { $0.status != .pending }
        let followed = resolved.filter { $0.status == .eaten }.count
        let swapped = resolved.filter { $0.status == .swapped }.count
        let skipped = resolved.filter { $0.status == .skipped }.count
        let onTime = planned.filter(\.plannedOnTime).count
        let fullDays = elapsedDays.filter { FoodRules.isDayPlanned($0, entries: entries) }.count

        return Section("Plan") {
            LabeledContent("Plan followed", value: percent(followed, of: followed + swapped))
            LabeledContent("Ate as planned / something else / skipped", value: "\(followed) / \(swapped) / \(skipped)")
            LabeledContent("Planned the day before", value: percent(onTime, of: planned.count))
            LabeledContent("Days fully planned", value: "\(fullDays) of \(elapsedDays.count)")
            LabeledContent("Breaks snoozed", value: "\(inWindow.filter { $0.snoozeCount > 0 }.count) (\(inWindow.reduce(0) { $0 + $1.snoozeCount }) snoozes)")
        }
    }

    // MARK: Calories

    private var caloriesSection: some View {
        let perDay = elapsedDays.map { d in (d, FoodRules.entries(on: d, entries).reduce(0) { $0 + $1.eatenCalories }) }
        let logged = perDay.filter { $0.1 > 0 }
        let average = logged.isEmpty ? 0 : logged.map(\.1).reduce(0, +) / Double(logged.count)
        let over = logged.filter { $0.1 > Double(dailyCalories) }.count
        let unplannedKcal = inWindow.filter { FoodRules.cheatReason($0) != nil }.reduce(0) { $0 + $1.eatenCalories }

        return Section("Calories") {
            LabeledContent("Average per day", value: "\(Int(average)) / \(dailyCalories)")
            LabeledContent("Days over target", value: "\(over) of \(logged.count)")
            LabeledContent("From cheats", value: "\(Int(unplannedKcal)) kcal")
            Picker("Chart", selection: $calorieView) {
                ForEach(CalorieView.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            calorieChart
        }
    }

    @ViewBuilder
    private var calorieChart: some View {
        let cal = Calendar.current
        switch calorieView {
        case .day:
            // Each day of the selected period, up to today.
            let bars = elapsedDays.flatMap { calorieBars($0, cal.date(byAdding: .day, value: 1, to: $0)!) }
            chart(bars, unit: .day, target: Double(dailyCalories), targetLabel: "Daily target")
            Text("Each day of this \(period.title.lowercased()). Red is calories from cheats.")
                .font(.caption).foregroundStyle(.secondary)
        case .week:
            // The last 8 weeks, ending with the week this period ends in.
            let last = GoalPeriod.week.start(for: min(Date(), windowEnd.addingTimeInterval(-1)))
            let starts = (0..<8).reversed().map { cal.date(byAdding: .weekOfYear, value: -$0, to: last)! }
            let bars = starts.flatMap { calorieBars($0, GoalPeriod.week.next(after: $0)) }
            chart(bars, unit: .weekOfYear, target: Double(dailyCalories * 7), targetLabel: "Weekly target")
            Text("Total per week for the last 8 weeks. The newest week may still be in progress.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chart(_ bars: [CalorieBar], unit: Calendar.Component, target: Double, targetLabel: String) -> some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(x: .value("Date", bar.start, unit: unit), y: .value("kcal", bar.kcal))
                    .foregroundStyle(by: .value("From", bar.kind))
            }
            RuleMark(y: .value(targetLabel, target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("\(targetLabel) \(Int(target))").font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(["Planned": Color.green, "Cheats": Color.red])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: unit == .day ? .dateTime.day() : .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 180)
    }

    // MARK: Money

    private var moneySection: some View {
        let spent = inWindow.reduce(0) { $0 + $1.eatenCost }
        let onCheats = inWindow.filter { FoodRules.cheatReason($0) != nil }.reduce(0) { $0 + $1.eatenCost }
        let budget = weeklyBudget * weeksInWindow
        return Section("Money") {
            LabeledContent("Spent", value: budget > 0 ? "\(FoodSettings.money(spent)) / \(FoodSettings.money(budget))" : FoodSettings.money(spent))
                .foregroundStyle(budget > 0 && spent > budget ? .red : .primary)
            LabeledContent("Spent on cheats", value: FoodSettings.money(onCheats))
        }
    }

    // MARK: Cravings & triggers

    private var cravingsSection: some View {
        let list = cravings.filter { $0.date >= windowStart && $0.date < windowEnd }
        let resisted = list.filter(\.resisted).count
        return Section("Cravings") {
            LabeledContent("Resisted", value: "\(resisted) of \(list.count)")
        }
    }

    private var triggersSection: some View {
        let cheatTriggers = FoodRules.cheats(inWindow).map(\.trigger)
        let cravingTriggers = cravings.filter { $0.date >= windowStart && $0.date < windowEnd }.map(\.trigger)
        let counts = Dictionary(grouping: (cheatTriggers + cravingTriggers).filter { !$0.isEmpty }, by: { $0 })
            .mapValues(\.count).sorted { $0.value > $1.value }
        let total = counts.map(\.value).reduce(0, +)

        let buckets: [(String, ClosedRange<Int>)] = [("Morning (5–11)", 5...10), ("Midday (11–3)", 11...14),
                                                      ("Afternoon (3–6)", 15...17), ("Evening (6–10)", 18...21)]
        let cheatHours = FoodRules.cheats(inWindow).map { Calendar.current.component(.hour, from: $0.eatenAt ?? $0.time) }

        return Section("When and why") {
            if total == 0 {
                Text("No triggers recorded yet.").foregroundStyle(.secondary)
            }
            ForEach(counts, id: \.key) { item in
                LabeledContent(item.key, value: "\(item.value) · \(percent(item.value, of: total))")
            }
            ForEach(buckets, id: \.0) { bucket in
                LabeledContent(bucket.0, value: "\(cheatHours.filter { bucket.1.contains($0) }.count) cheats")
            }
            LabeledContent("Night (10–5)", value: "\(cheatHours.filter { $0 >= 22 || $0 < 5 }.count) cheats")
        }
    }

    private func percent(_ part: Int, of whole: Int) -> String {
        whole == 0 ? "–" : "\(Int((Double(part) / Double(whole) * 100).rounded()))%"
    }
}
