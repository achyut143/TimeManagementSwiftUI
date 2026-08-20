import SwiftUI
import SwiftData
import Charts

// Timeline chart for projects, switchable via a segmented control:
//  - "Projects": one line per project, value = total time logged to that
//    project within the bucket (activities + direct project time).
//  - "Virtues": one line per project virtue (Project.virtues) — value = total
//    time logged, summed across every project that carries that virtue, so a
//    project's logged time counts toward each of its virtues. Unlike the
//    Task/Habit trends chart, the value plotted here is TIME, not a count.
// Bucketed by Day/Week/Month/Year (default Week), showing the 7 most recent
// buckets with Previous/Next paging 7 buckets at a time. Mirrors
// VirtueHabitTrendsView's structure.
struct ProjectTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var projects: [Project]

    enum Mode: String, CaseIterable, Identifiable {
        case projects = "Projects"
        case virtues = "Virtues"
        var id: String { rawValue }
    }

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .projects
    @State private var granularity: Granularity = .week
    // Anchor date for the *end* of the visible 7-bucket window; paging shifts this.
    @State private var windowEndAnchor = Date()
    // Tap/drag-selected bucket (nearest snapped via chartXSelection); 0 = most
    // recent bucket, shown by default so the readout is visible immediately.
    @State private var selectedBucketIndex: Int? = 0

    // Which chips are hidden, persisted per mode, same pattern as
    // VirtueHabitTrendsView — survives leaving and reopening this view.
    @AppStorage("projectTrends.hiddenProjects") private var hiddenProjectsRaw: String = ""
    @AppStorage("projectTrends.hiddenVirtues") private var hiddenVirtuesRaw: String = ""

    private let calendar = Calendar.current

    struct Bucket: Identifiable {
        let id = Int.random(in: Int.min...Int.max)
        let index: Int
        let start: Date
        let lastDay: Date // inclusive last day, matches Project.totalMinutes's <= comparisons
        let label: String
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let bucketIndex: Int
        let seriesName: String
        let minutes: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases) { g in Text(g.rawValue).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: granularity) { _, _ in windowEndAnchor = Date() }

                    pagerHeader

                    if seriesNames.isEmpty {
                        Text(mode == .projects
                             ? "No projects yet."
                             : "No virtues added to any project yet. Add some from a project's Virtues button.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        chartView

                        Divider()

                        HStack {
                            Text("Show")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Select All") { showAll() }
                                .font(.caption)
                            Button("None") { hideAll() }
                                .font(.caption)
                        }
                        seriesChips
                        Text("Tip: tap-and-hold a chip to show only that one — many overlapping lines get hard to read.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(mode == .projects ? "Project Time Trends" : "Project Virtue Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header / paging

    private var pagerHeader: some View {
        HStack {
            Button {
                windowEndAnchor = shift(windowEndAnchor, byBuckets: -7)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            if let first = buckets.first, let last = buckets.last {
                Text("\(first.label) – \(last.label)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Spacer()

            Button {
                windowEndAnchor = shift(windowEndAnchor, byBuckets: 7)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isAtPresent)
        }
        .buttonStyle(.bordered)
    }

    private var isAtPresent: Bool {
        guard let last = buckets.last else { return true }
        return bucketEnd(start: last.start) > Date()
    }

    // MARK: - Chart

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if let selectedBucketIndex {
                    RuleMark(x: .value("Selected", selectedBucketIndex))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }

                ForEach(filteredPoints) { point in
                    LineMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(by: .value("Name", point.seriesName))
                    .symbol(by: .value("Name", point.seriesName))

                    PointMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(by: .value("Name", point.seriesName))
                }
            }
            .chartXSelection(value: $selectedBucketIndex)
            .chartXAxis {
                AxisMarks(values: buckets.map { $0.index }) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let idx = value.as(Int.self), let bucket = buckets.first(where: { $0.index == idx }) {
                            Text(bucket.label)
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text(DurationInput.string(from: minutes))
                        }
                    }
                }
            }
            .chartYAxisLabel("Time")
            .frame(height: 260)

            selectionReadout
        }
    }

    // Tap or drag anywhere on the chart to snap to the nearest period and see
    // every visible series' exact logged time there, instead of eyeballing
    // the line against the Y axis.
    @ViewBuilder
    private var selectionReadout: some View {
        if let selectedBucketIndex, let bucket = buckets.first(where: { $0.index == selectedBucketIndex }) {
            let rows = filteredPoints.filter { $0.bucketIndex == selectedBucketIndex }.sorted { $0.minutes > $1.minutes }
            VStack(alignment: .leading, spacing: 4) {
                Text(bucket.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                if rows.isEmpty {
                    Text("No visible series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { row in
                        HStack {
                            Text(row.seriesName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(DurationInput.string(from: row.minutes))
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var filteredPoints: [TrendPoint] {
        let hidden = hiddenSeries
        return allPoints.filter { !hidden.contains($0.seriesName) }
    }

    // MARK: - Series toggles

    private var seriesChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(seriesNames, id: \.self) { name in
                chip(for: name)
            }
        }
    }

    private func chip(for name: String) -> some View {
        let isOn = !hiddenSeries.contains(name)
        return Button {
            toggleHidden(name)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                Text(name)
                    .lineLimit(1)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isOn ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
            .foregroundStyle(isOn ? Color.blue : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onLongPressGesture {
            isolate(name)
        }
    }

    // MARK: - Hidden-series persistence

    private var hiddenSeries: Set<String> {
        Set(decodeNames(mode == .projects ? hiddenProjectsRaw : hiddenVirtuesRaw))
    }

    private func toggleHidden(_ name: String) {
        var current = decodeNames(mode == .projects ? hiddenProjectsRaw : hiddenVirtuesRaw)
        if let idx = current.firstIndex(of: name) {
            current.remove(at: idx)
        } else {
            current.append(name)
        }
        setHidden(current)
    }

    // Un-hides everything.
    private func showAll() {
        setHidden([])
    }

    // Hides every series currently in view.
    private func hideAll() {
        setHidden(seriesNames)
    }

    // Hides everything except `name` — the fast path for "too many overlapping
    // lines, just show me this one" instead of tapping every other chip off.
    private func isolate(_ name: String) {
        setHidden(seriesNames.filter { $0 != name })
    }

    private func setHidden(_ names: [String]) {
        let encoded = encodeNames(names)
        if mode == .projects {
            hiddenProjectsRaw = encoded
        } else {
            hiddenVirtuesRaw = encoded
        }
    }

    private func decodeNames(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return array
    }

    private func encodeNames(_ names: [String]) -> String {
        guard let data = try? JSONEncoder().encode(names),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    // MARK: - Data

    private var seriesNames: [String] {
        switch mode {
        case .projects:
            return projects.map { $0.name }.sorted()
        case .virtues:
            return Array(Set(projects.flatMap { $0.virtues })).sorted()
        }
    }

    private var allPoints: [TrendPoint] {
        let names = seriesNames
        guard !names.isEmpty else { return [] }

        var points: [TrendPoint] = []
        for bucket in buckets {
            var minutesByName: [String: Double] = [:]
            switch mode {
            case .projects:
                for project in projects {
                    minutesByName[project.name, default: 0] += project.totalMinutes(from: bucket.start, to: bucket.lastDay)
                }
            case .virtues:
                for project in projects where !project.virtues.isEmpty {
                    let projectMinutes = project.totalMinutes(from: bucket.start, to: bucket.lastDay)
                    guard projectMinutes > 0 else { continue }
                    for virtue in project.virtues {
                        minutesByName[virtue, default: 0] += projectMinutes
                    }
                }
            }

            for name in names {
                points.append(TrendPoint(bucketIndex: bucket.index, seriesName: name, minutes: minutesByName[name] ?? 0))
            }
        }
        return points
    }

    // MARK: - Bucketing

    private var buckets: [Bucket] {
        let anchorStart = bucketStart(for: windowEndAnchor)
        var result: [Bucket] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let start = shift(anchorStart, byBuckets: -i)
            let lastDay = calendar.date(byAdding: .day, value: -1, to: bucketEnd(start: start)) ?? start
            result.append(Bucket(index: -i, start: start, lastDay: lastDay, label: label(for: start)))
        }
        return result
    }

    private func bucketStart(for date: Date) -> Date {
        switch granularity {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let start = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: start) // 1=Sun...7=Sat
            let daysSinceMonday = (weekday + 5) % 7
            return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: comps) ?? date
        case .year:
            let comps = calendar.dateComponents([.year], from: date)
            return calendar.date(from: comps) ?? date
        }
    }

    private func bucketEnd(start: Date) -> Date {
        switch granularity {
        case .day: return calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week: return calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month: return calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .year: return calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }
    }

    private func shift(_ date: Date, byBuckets n: Int) -> Date {
        switch granularity {
        case .day: return calendar.date(byAdding: .day, value: n, to: date) ?? date
        case .week: return calendar.date(byAdding: .day, value: 7 * n, to: date) ?? date
        case .month: return calendar.date(byAdding: .month, value: n, to: date) ?? date
        case .year: return calendar.date(byAdding: .year, value: n, to: date) ?? date
        }
    }

    private func label(for start: Date) -> String {
        let formatter = DateFormatter()
        switch granularity {
        case .day:
            formatter.dateFormat = "MMM d"
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM yyyy"
        case .year:
            formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: start)
    }
}
