import SwiftUI
import SwiftData
import Charts

/// Planned vs unplanned impulse time across weeks, months or quarters, broken down by
/// impulse type, time of day and weekday. Counts only impulses that have happened.
struct ImpulseInsightsView: View {
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
    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let kindColors: KeyValuePairs<String, Color> = ["Planned": .green, "Unplanned": .red]

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

    private struct HourPoint: Identifiable {
        let id = UUID()
        let hour: Int
        let kind: String
        let hours: Double
    }

    private struct SharePoint: Identifiable {
        let id = UUID()
        let label: String
        let percent: Double
    }

    private var count: Int {
        switch period {
        case .week, .quarter: return 8
        default: return 12
        }
    }

    private var noImpulseDays: Set<Date> { Set(days.filter(\.noImpulseDay).map(\.date)) }

    private var selectedType: ImpulseType? { types.first { $0.id == typeID } }

    private var filteredTasks: [Task] {
        guard let typeID else { return impulseTasks }
        return impulseTasks.filter { $0.impulseTypeID == typeID }
    }

    /// Period starts, oldest first.
    private var starts: [Date] {
        var start = period.start(for: anchor)
        for _ in 0..<(windowsBack * count) { start = period.previous(before: start) }
        var result = [start]
        for _ in 1..<count { result.insert(period.previous(before: result[0]), at: 0) }
        return result
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
        let starts = starts
        let windowEnd = period.next(after: starts.last!)
        let noImpulse = noImpulseDays
        let windowTasks = ImpulseRules.tasks(filteredTasks, from: starts.first!, to: windowEnd)
        let happened = windowTasks.filter { ImpulseRules.hasHappened($0) }
        let rows = starts.map { s in
            Row(start: s, split: ImpulseRules.split(ImpulseRules.tasks(windowTasks, from: s, to: period.next(after: s)), noImpulseDays: noImpulse))
        }
        let total = rows.reduce(into: ImpulseRules.Split()) { $0.add($1.split) }

        List {
            controls(rows)

            Section {
                summaryGrid(total, happened: happened)
            } footer: {
                Text("Only impulses marked done or already past their end time are counted." +
                     (total.aheadCount > 0 ? " \(total.aheadCount) scheduled ahead (\(PlannerRules.formatMinutes(total.aheadMinutes))) aren't counted yet." : ""))
            }

            let notes = insights(rows: rows, happened: happened, noImpulseDays: noImpulse)
            if !notes.isEmpty {
                Section("Insights") {
                    ForEach(notes, id: \.self) { note in
                        Label(note, systemImage: "lightbulb").font(.subheadline)
                    }
                }
            }

            Section("Over time") {
                trendChart(rows)
                shareChart(rows)
            }

            if typeID == nil {
                byTypeSection(windowTasks: windowTasks, noImpulseDays: noImpulse)
            } else if let type = selectedType {
                typeDetailSection(type, happened: happened, noImpulseDays: noImpulse)
            }

            Section("When impulses happen") {
                hourChart(happened, noImpulseDays: noImpulse)
                weekdayChart(happened, noImpulseDays: noImpulse)
            }

            Section("By \(period.title.lowercased())") {
                ForEach(rows.reversed()) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(period.label(for: row.start))
                            Spacer()
                            Text(percent(row.split.planned, of: row.split.total)).foregroundStyle(.secondary)
                        }
                        Text(detail(for: row)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(selectedType.map { "\($0.name) Insights" } ?? "Impulse Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Controls

    @ViewBuilder
    private func controls(_ rows: [Row]) -> some View {
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
    }

    // MARK: - Summary

    private func summaryGrid(_ total: ImpulseRules.Split, happened: [Task]) -> some View {
        let avg = total.count > 0 ? total.total / Double(total.count) : 0
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            tile("Total", PlannerRules.formatMinutes(total.total), "\(total.count) times", .primary)
            tile("Planned", percent(total.planned, of: total.total), PlannerRules.formatMinutes(total.planned), .green)
            tile("Unplanned", PlannerRules.formatMinutes(total.unplanned), "\(total.unplannedCount) times", .red)
            tile("Avg session", total.count > 0 ? PlannerRules.formatMinutes(avg) : "–", "per impulse", .primary)
            tile("Overran", PlannerRules.formatMinutes(total.overrun), "past planned end", .orange)
            tile("Resisted", "\(total.skippedCount)", "marked not done", .blue)
        }
        .padding(.vertical, 4)
    }

    private func tile(_ title: String, _ value: String, _ caption: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Insights

    private func insights(rows: [Row], happened: [Task], noImpulseDays: Set<Date>) -> [String] {
        var notes: [String] = []

        // Latest finished-or-current period against the one before it.
        let withData = rows.filter { $0.split.total > 0 }
        if withData.count >= 2, let a = withData.last?.split.plannedShare, let b = withData.dropLast().last?.split.plannedShare {
            let change = Int(((a - b) * 100).rounded())
            if change != 0 {
                notes.append("Planned share \(change > 0 ? "up" : "down") \(abs(change)) points in the latest \(period.title.lowercased()) with impulses.")
            }
        }

        if typeID == nil {
            let worst = types.map { type -> (ImpulseType, Double) in
                let s = ImpulseRules.split(happened.filter { $0.impulseTypeID == type.id }, noImpulseDays: noImpulseDays)
                return (type, s.unplanned)
            }.max { $0.1 < $1.1 }
            if let worst, worst.1 > 0 {
                notes.append("\(worst.0.name) has the most unplanned time (\(PlannerRules.formatMinutes(worst.1))).")
            }
        }

        let hours = unplannedByHour(happened, noImpulseDays: noImpulseDays)
        if let peak = hours.max(by: { $0.value < $1.value }), peak.value > 0 {
            notes.append("Unplanned impulses start most often around \(hourLabel(peak.key, long: true)).")
        }

        let byDay = minutesByWeekday(happened)
        if let peak = byDay.enumerated().max(by: { $0.element < $1.element }), peak.element > 0 {
            notes.append("\(Self.weekdays[peak.offset]) is your heaviest impulse day.")
        }

        let total = ImpulseRules.split(happened, noImpulseDays: noImpulseDays)
        if total.total > 0, total.overrun / total.total >= 0.15 {
            notes.append("\(percent(total.overrun, of: total.total)) of impulse time is overrun — sessions run past their planned end.")
        }
        return notes
    }

    // MARK: - Charts

    private func trendChart(_ rows: [Row]) -> some View {
        let points = rows.flatMap { r in
            [Point(label: shortLabel(r.start), kind: "Planned", hours: r.split.planned / 60),
             Point(label: shortLabel(r.start), kind: "Unplanned", hours: r.split.unplanned / 60)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Hours per \(period.title.lowercased())").font(.caption).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Period", p.label), y: .value("Hours", p.hours))
                    .foregroundStyle(by: .value("Kind", p.kind))
            }
            .chartForegroundStyleScale(Self.kindColors)
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
            .frame(height: 180)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func shareChart(_ rows: [Row]) -> some View {
        let points = rows.compactMap { r in
            r.split.plannedShare.map { SharePoint(label: shortLabel(r.start), percent: $0 * 100) }
        }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Planned share (%)").font(.caption).foregroundStyle(.secondary)
                Chart(points) { p in
                    LineMark(x: .value("Period", p.label), y: .value("Planned %", p.percent))
                        .foregroundStyle(.green)
                    PointMark(x: .value("Period", p.label), y: .value("Planned %", p.percent))
                        .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
                .frame(height: 120)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func byTypeSection(windowTasks: [Task], noImpulseDays: Set<Date>) -> some View {
        let stats = types.map { type in
            (type, ImpulseRules.split(windowTasks.filter { $0.impulseTypeID == type.id }, noImpulseDays: noImpulseDays))
        }
        .filter { $0.1.total > 0 || $0.1.skippedCount > 0 }
        .sorted { $0.1.total > $1.1.total }

        Section {
            if stats.isEmpty {
                Text("No impulses in this range").foregroundStyle(.secondary)
            } else {
                let points = stats.flatMap { type, s in
                    [Point(label: type.name, kind: "Planned", hours: s.planned / 60),
                     Point(label: type.name, kind: "Unplanned", hours: s.unplanned / 60)]
                }
                Chart(points) { p in
                    BarMark(x: .value("Hours", p.hours), y: .value("Type", p.label))
                        .foregroundStyle(by: .value("Kind", p.kind))
                }
                .chartForegroundStyleScale(Self.kindColors)
                .frame(height: CGFloat(stats.count) * 32 + 40)
                .padding(.vertical, 4)

                ForEach(stats, id: \.0.id) { type, s in
                    Button { typeID = type.id } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle().fill(type.color).frame(width: 10, height: 10)
                                Text(type.name).foregroundStyle(.primary)
                                Spacer()
                                Text(PlannerRules.formatMinutes(s.total)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(typeLine(s)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("By impulse type")
        } footer: {
            Text("Tap a type to see its own trend and timing.")
        }
    }

    private func typeLine(_ s: ImpulseRules.Split) -> String {
        var parts = ["\(percent(s.planned, of: s.total)) planned", "\(s.count) times"]
        if s.count > 0 { parts.append("avg \(PlannerRules.formatMinutes(s.total / Double(s.count)))") }
        if s.overrun > 0 { parts.append("\(PlannerRules.formatMinutes(s.overrun)) overrun") }
        if s.skippedCount > 0 { parts.append("\(s.skippedCount) resisted") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func typeDetailSection(_ type: ImpulseType, happened: [Task], noImpulseDays: Set<Date>) -> some View {
        // How far ahead the planned sessions were scheduled.
        let leads = happened.compactMap { t -> Double? in
            guard ImpulseRules.isPlannedLabel(t), let start = ImpulseRules.startDate(of: t), let checked = t.impulseCheckedAt else { return nil }
            return start.timeIntervalSince(checked) / 3600
        }
        let longest = happened.map { ImpulseRules.actualMinutes(of: $0) }.max() ?? 0
        Section {
            HStack {
                Circle().fill(type.color).frame(width: 10, height: 10)
                Text("Plan at least \(PlannerRules.formatHours(type.planBeforeHours * 60))h ahead")
            }
            metric("Avg lead time when planned", leads.isEmpty ? "–" : "\(PlannerRules.formatHours(leads.reduce(0, +) / Double(leads.count) * 60))h ahead")
            metric("Longest session", longest > 0 ? PlannerRules.formatMinutes(longest) : "–")
            Button("Show all types") { typeID = nil }
        } header: {
            Text(type.name)
        }
    }

    private func unplannedByHour(_ tasks: [Task], noImpulseDays: Set<Date>) -> [Int: Double] {
        var result: [Int: Double] = [:]
        for t in tasks {
            guard let start = ImpulseRules.startDate(of: t) else { continue }
            let noImpulse = t.date.map { noImpulseDays.contains($0.startOfDay) } ?? false
            result[Calendar.current.component(.hour, from: start), default: 0] += ImpulseRules.unplannedMinutes(of: t, noImpulseDay: noImpulse)
        }
        return result
    }

    private func hourChart(_ tasks: [Task], noImpulseDays: Set<Date>) -> some View {
        var planned = [Double](repeating: 0, count: 24)
        var unplanned = [Double](repeating: 0, count: 24)
        for t in tasks {
            guard let start = ImpulseRules.startDate(of: t) else { continue }
            let h = Calendar.current.component(.hour, from: start)
            let noImpulse = t.date.map { noImpulseDays.contains($0.startOfDay) } ?? false
            planned[h] += ImpulseRules.plannedMinutes(of: t, noImpulseDay: noImpulse)
            unplanned[h] += ImpulseRules.unplannedMinutes(of: t, noImpulseDay: noImpulse)
        }
        let points = (0..<24).flatMap { h in
            [HourPoint(hour: h, kind: "Planned", hours: planned[h] / 60),
             HourPoint(hour: h, kind: "Unplanned", hours: unplanned[h] / 60)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("By start time (hours)").font(.caption).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Hour", p.hour), y: .value("Hours", p.hours), width: .ratio(0.8))
                    .foregroundStyle(by: .value("Kind", p.kind))
            }
            .chartForegroundStyleScale(Self.kindColors)
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text(hourLabel(v.as(Int.self) ?? 0, long: false)).font(.caption2) }
                }
            }
            .frame(height: 140)
        }
        .padding(.vertical, 4)
    }

    private func minutesByWeekday(_ tasks: [Task]) -> [Double] {
        var result = [Double](repeating: 0, count: 7)
        for t in tasks {
            guard let d = t.date else { continue }
            let weekday = Calendar.current.component(.weekday, from: d) // 1 = Sun
            result[(weekday + 5) % 7] += ImpulseRules.actualMinutes(of: t)
        }
        return result
    }

    private func weekdayChart(_ tasks: [Task], noImpulseDays: Set<Date>) -> some View {
        var planned = [Double](repeating: 0, count: 7)
        var unplanned = [Double](repeating: 0, count: 7)
        for t in tasks {
            guard let d = t.date else { continue }
            let i = (Calendar.current.component(.weekday, from: d) + 5) % 7
            let noImpulse = noImpulseDays.contains(d.startOfDay)
            planned[i] += ImpulseRules.plannedMinutes(of: t, noImpulseDay: noImpulse)
            unplanned[i] += ImpulseRules.unplannedMinutes(of: t, noImpulseDay: noImpulse)
        }
        let points = (0..<7).flatMap { i in
            [Point(label: Self.weekdays[i], kind: "Planned", hours: planned[i] / 60),
             Point(label: Self.weekdays[i], kind: "Unplanned", hours: unplanned[i] / 60)]
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("By weekday (hours)").font(.caption).foregroundStyle(.secondary)
            Chart(points) { p in
                BarMark(x: .value("Day", p.label), y: .value("Hours", p.hours))
                    .foregroundStyle(by: .value("Kind", p.kind))
            }
            .chartForegroundStyleScale(Self.kindColors)
            .frame(height: 140)
        }
        .padding(.vertical, 4)
    }

    private func hourLabel(_ hour: Int, long: Bool) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return long ? date.formatted(date: .omitted, time: .shortened) : date.formatted(.dateTime.hour())
    }

    // MARK: - Rows

    private func detail(for row: Row) -> String {
        var text = "\(PlannerRules.formatMinutes(row.split.planned)) planned, \(PlannerRules.formatMinutes(row.split.unplanned)) unplanned"
        if row.split.skippedCount > 0 { text += " · \(row.split.skippedCount) resisted" }
        if row.split.aheadCount > 0 { text += " · \(PlannerRules.formatMinutes(row.split.aheadMinutes)) ahead" }
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
