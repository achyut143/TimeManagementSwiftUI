import SwiftUI
import SwiftData
import Charts

/// Hours, points and completion for tasks grouped by Goal over a date range.
/// Pick one or more goals (or "No Goal") to narrow it down; nothing picked
/// means all tasks. Replaces the old tag-based analytics.
struct GoalAnalyticsView: View {
    @Query private var tasks: [Task]
    @Query(sort: \Goal.name) private var goals: [Goal]

    /// Goal UUID strings, plus `noGoalKey` for tasks without a goal.
    @State private var selectedGoals: Set<String> = []
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()

    private static let noGoalKey = "none"
    private static let noGoalName = "No Goal"

    // MARK: Data

    private struct DayRow: Identifiable {
        let id = UUID()
        let day: Date
        let goal: String
        let hours: Double
        let points: Double
    }

    private struct GoalRow: Identifiable {
        let id: String
        let name: String
        var hours = 0.0
        var points = 0.0
        var completed = 0
        var scheduled = 0
        var rate: Double { scheduled > 0 ? Double(completed) / Double(scheduled) : 0 }
    }

    private struct Computed {
        var days: [DayRow] = []
        var goals: [GoalRow] = []
        var totalHours = 0.0
        var totalPoints = 0.0
        var completed = 0
        var scheduled = 0
    }

    private func key(for task: Task) -> String {
        task.goal?.id.uuidString ?? Self.noGoalKey
    }

    private func name(forKey key: String) -> String {
        key == Self.noGoalKey ? Self.noGoalName : (goals.first { $0.id.uuidString == key }?.name ?? "Goal")
    }

    /// One pass over the tasks: per-day hours/points (completed tasks) and
    /// per-goal completion (all scheduled tasks) within the range.
    private var computed: Computed {
        let cal = Calendar.current
        let rangeStart = cal.startOfDay(for: min(startDate, endDate))
        let rangeEnd = cal.startOfDay(for: max(startDate, endDate))

        var byDayGoal: [Date: [String: (Double, Double)]] = [:]
        var byGoal: [String: GoalRow] = [:]
        var result = Computed()

        for task in tasks {
            guard let date = task.date else { continue }
            let day = cal.startOfDay(for: date)
            guard day >= rangeStart && day <= rangeEnd else { continue }
            let k = key(for: task)
            guard selectedGoals.isEmpty || selectedGoals.contains(k) else { continue }

            var row = byGoal[k] ?? GoalRow(id: k, name: name(forKey: k))
            row.scheduled += 1
            result.scheduled += 1

            if task.completed {
                let hours = task.effectiveTimeInMinutes / 60.0
                let points = task.effectiveWeight
                row.completed += 1
                row.hours += hours
                row.points += points
                result.completed += 1
                result.totalHours += hours
                result.totalPoints += points
                let prev = byDayGoal[day, default: [:]][k] ?? (0, 0)
                byDayGoal[day, default: [:]][k] = (prev.0 + hours, prev.1 + points)
            }
            byGoal[k] = row
        }

        result.goals = byGoal.values.sorted { $0.hours > $1.hours }
        for (day, goalMap) in byDayGoal {
            for (k, v) in goalMap {
                result.days.append(DayRow(day: day, goal: name(forKey: k), hours: v.0, points: v.1))
            }
        }
        result.days.sort { $0.day < $1.day }
        return result
    }

    // MARK: Body

    var body: some View {
        let data = computed
        ScrollView {
            VStack(spacing: 20) {
                statsCard(data)
                dateFilterSection
                goalPicker
                breakdownSection(data)
                chartSection(data)
            }
            .padding()
        }
        .navigationTitle("Goal Analytics")
        .background(Color(.systemGroupedBackground))
    }

    private func statsCard(_ data: Computed) -> some View {
        HStack(spacing: 12) {
            stat("Hours", String(format: "%.1f", data.totalHours), .primary)
            Divider()
            stat("Points", String(format: "%.1f", data.totalPoints), .green)
            Divider()
            stat("Done", "\(data.completed)/\(data.scheduled)", .blue)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)
            DateRangeShiftControl(start: $startDate, end: $endDate)
            HStack {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Goals")
                    .font(.headline)
                Spacer()
                if !selectedGoals.isEmpty {
                    Button("Show all") { selectedGoals.removeAll() }
                        .font(.caption)
                }
            }
            if goals.isEmpty {
                Text("No goals yet. Create them in the Goals tab and assign them to tasks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(goals) { goal in
                        chip(goal.name, key: goal.id.uuidString)
                    }
                    chip(Self.noGoalName, key: Self.noGoalKey)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private func chip(_ title: String, key: String) -> some View {
        let on = selectedGoals.contains(key)
        return Button(title) {
            if on { selectedGoals.remove(key) } else { selectedGoals.insert(key) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(on ? Color.blue : Color.gray.opacity(0.15))
        .foregroundColor(on ? .white : .primary)
        .cornerRadius(20)
        .font(.subheadline)
    }

    /// Per-goal hours, points and completion rate.
    private func breakdownSection(_ data: Computed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By Goal")
                .font(.headline)
            if data.goals.isEmpty {
                Text("No tasks in this range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(data.goals) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1fh · %.0f pts", row.hours, row.points))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: row.rate)
                        .tint(row.rate >= 0.8 ? .green : (row.rate >= 0.5 ? .orange : .red))
                    Text("\(row.completed) of \(row.scheduled) done · \(Int(row.rate * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    private func chartSection(_ data: Computed) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(selectedGoals.isEmpty
                 ? "All Completed Tasks"
                 : "Selected: " + selectedGoals.map(name(forKey:)).sorted().joined(separator: ", "))
                .font(.headline)

            dailyChart(title: "Hours Spent", rows: data.days, value: \.hours, label: "Hours")
            dailyChart(title: "Points Earned", rows: data.days, value: \.points, label: "Points")
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }

    /// Daily bars, stacked and colored by goal.
    private func dailyChart(title: String, rows: [DayRow], value: KeyPath<DayRow, Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Chart(rows) { row in
                BarMark(
                    x: .value("Date", row.day, unit: .day),
                    y: .value(label, row[keyPath: value])
                )
                .foregroundStyle(by: .value("Goal", row.goal))
            }
            .chartXScale(domain: chartDomain)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 220)
        }
    }

    /// Keeps empty days visible on the x-axis.
    private var chartDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.startOfDay(for: min(startDate, endDate))
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(startDate, endDate))) ?? start
        return start...end
    }
}
