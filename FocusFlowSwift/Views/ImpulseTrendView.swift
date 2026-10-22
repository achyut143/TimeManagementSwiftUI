import SwiftUI
import SwiftData
import Charts

/// Planned vs unplanned impulse time across weeks, months or quarters.
struct ImpulseTrendView: View {
    /// The newest period shown contains this date.
    let anchor: Date

    @Query private var days: [PlannerDay]
    @Query(sort: \ImpulseType.sortOrder) private var types: [ImpulseType]
    @Query private var budgets: [ImpulseBudgetVersion]
    @Query(filter: #Predicate<Task> { $0.impulseTypeID != nil }) private var impulseTasks: [Task]

    @State private var period: GoalPeriod = .week
    /// How many whole windows back from the anchor.
    @State private var windowsBack = 0
    @State private var typeID: UUID?

    private static let periods: [GoalPeriod] = [.week, .month, .quarter]

    private struct Row: Identifiable {
        let start: Date
        let split: ImpulseRules.Split
        var id: Date { start }
    }

    private struct Point: Identifiable {
        let id = UUID()
        let label: String
        let kind: String
        let hours: Double
    }

    private var count: Int {
        switch period {
        case .week, .quarter: return 8
        default: return 12
        }
    }

    private var noImpulseDays: Set<Date> { Set(days.filter(\.noImpulseDay).map(\.date)) }

    private var filteredTasks: [Task] {
        guard let typeID else { return impulseTasks }
        return impulseTasks.filter { $0.impulseTypeID == typeID }
    }

    /// Oldest first.
    private var rows: [Row] {
        var start = period.start(for: anchor)
        for _ in 0..<(windowsBack * count) { start = period.previous(before: start) }
        var starts = [start]
        for _ in 1..<count { starts.insert(period.previous(before: starts[0]), at: 0) }
        let noImpulse = noImpulseDays
        return starts.map { s in
            let tasks = ImpulseRules.tasks(filteredTasks, from: s, to: period.next(after: s))
            return Row(start: s, split: ImpulseRules.split(tasks, noImpulseDays: noImpulse))
        }
    }

    private func shortLabel(_ start: Date) -> String {
        switch period {
        case .week: return start.formatted(.dateTime.month(.defaultDigits).day())
        case .month: return start.formatted(.dateTime.month(.abbreviated)) // 12 in a row never repeat; bars with the same label would merge
        default:
            let c = Calendar.current.dateComponents([.year, .month], from: start)
            return "Q\((c.month! - 1) / 3 + 1) '\(c.year! % 100)"
        }
    }

    var body: some View {
        let rows = rows
        let total = rows.reduce(into: ImpulseRules.Split()) { acc, r in
            acc.planned += r.split.planned
            acc.unplanned += r.split.unplanned
            acc.plannedCount += r.split.plannedCount
            acc.unplannedCount += r.split.unplannedCount
        }
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Self.periods) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { windowsBack = 0 }

                Picker("Impulse type", selection: $typeID) {
                    Text("All types").tag(UUID?.none)
                    ForEach(types) { Text($0.name).tag(UUID?.some($0.id)) }
                }

                HStack {
                    Button { windowsBack += 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    if let first = rows.first, let last = rows.last {
                        Text("\(period.label(for: first.start)) – \(period.label(for: last.start))")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                    Button { windowsBack -= 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(windowsBack == 0)
                }
                .buttonStyle(.borderless)
            }

            Section {
                chart(rows)
                metric("Planned", "\(PlannerRules.formatMinutes(total.planned)) · \(total.plannedCount) tasks")
                metric("Unplanned", "\(PlannerRules.formatMinutes(total.unplanned)) · \(total.unplannedCount) tasks")
                metric("Planned share", percent(total.planned, of: total.total))
            }

            Section("By \(period.title.lowercased())") {
                ForEach(rows.reversed()) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(period.label(for: row.start))
                            Spacer()
                            Text(percent(row.split.planned, of: row.split.total))
                                .foregroundStyle(.secondary)
                        }
                        Text(detail(for: row))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Impulse Trend")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(_ rows: [Row]) -> some View {
        let points = rows.flatMap { r in
            [Point(label: shortLabel(r.start), kind: "Planned", hours: r.split.planned / 60),
             Point(label: shortLabel(r.start), kind: "Unplanned", hours: r.split.unplanned / 60)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Hours").font(.caption).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Period", p.label), y: .value("Hours", p.hours))
                    .foregroundStyle(by: .value("Kind", p.kind))
            }
            .chartForegroundStyleScale(["Planned": Color.green, "Unplanned": Color.red])
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2) }
            }
            .frame(height: 180)
        }
        .padding(.vertical, 4)
    }

    private func detail(for row: Row) -> String {
        var text = "\(PlannerRules.formatMinutes(row.split.planned)) planned, \(PlannerRules.formatMinutes(row.split.unplanned)) unplanned"
        // The budget is monthly and shared across types, so only compare a whole month of all types.
        if period == .month, typeID == nil,
           let budget = ImpulseRules.budgetMinutes(forMonthOf: row.start, versions: budgets) {
            text += " · \(percent(row.split.total, of: budget)) of \(PlannerRules.formatMinutes(budget)) budget"
        }
        return text
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func percent(_ part: Double, of whole: Double) -> String {
        whole > 0 ? "\(Int((part / whole * 100).rounded()))%" : "–"
    }
}
