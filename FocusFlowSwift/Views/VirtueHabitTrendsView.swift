import SwiftUI
import SwiftData
import Charts

// Timeline chart for two things, switchable via a segmented control:
//  - "Virtues": one line per virtue (Task.virtues), counted across all tasks
//    that carry it — so if two different tasks both have "Self-Discipline"
//    on the same day, that day's count for "Self-Discipline" is 2.
//  - "Habits": one line per repeat/routine task (grouped by title), counting
//    completed occurrences per period.
// Bucketed by Day/Week/Month/Year (default Week), showing the 7 most recent
// buckets with Previous/Next paging 7 buckets at a time.
struct VirtueHabitTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [Task]

    enum Mode: String, CaseIterable, Identifiable {
        case virtues = "Virtues"
        case habits = "Habits"
        var id: String { rawValue }
    }

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .virtues
    @State private var granularity: Granularity = .week
    // Anchor date for the *end* of the visible 7-bucket window; paging shifts this.
    @State private var windowEndAnchor = Date()
    // Tap/drag-selected bucket (nearest snapped via chartXSelection); 0 = most
    // recent bucket, shown by default so the readout is visible immediately.
    @State private var selectedBucketIndex: Int? = 0

    // Which chips are hidden, persisted per mode (as JSON-encoded arrays) so the
    // selection you leave with is exactly what you see when you come back to
    // this view — survives dismissing the sheet and relaunching the app.
    // Anything NOT in here is shown, so new virtues/habits default to visible.
    @AppStorage("virtueHabitTrends.hiddenVirtues") private var hiddenVirtuesRaw: String = ""
    @AppStorage("virtueHabitTrends.hiddenHabits") private var hiddenHabitsRaw: String = ""

    private let calendar = Calendar.current

    struct Bucket: Identifiable {
        let id = Int.random(in: Int.min...Int.max)
        let index: Int
        let start: Date
        let end: Date
        let label: String
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let bucketIndex: Int
        let seriesName: String
        let count: Int
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
                        Text(mode == .virtues
                             ? "No virtues added to any tasks yet. Add some from a task's Actions → Virtues."
                             : "No routine (repeat) tasks yet.")
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
            .navigationTitle(mode == .virtues ? "Virtue Trends" : "Habit Trends")
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
        return last.end > Date()
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
                        y: .value("Count", point.count)
                    )
                    .foregroundStyle(by: .value("Name", point.seriesName))
                    .symbol(by: .value("Name", point.seriesName))

                    PointMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value("Count", point.count)
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
            .chartYAxisLabel("Count")
            .frame(height: 260)

            selectionReadout
        }
    }

    // Tap or drag anywhere on the chart to snap to the nearest period and see
    // every visible series' exact value there, instead of eyeballing the line
    // against the Y axis.
    @ViewBuilder
    private var selectionReadout: some View {
        if let selectedBucketIndex, let bucket = buckets.first(where: { $0.index == selectedBucketIndex }) {
            let rows = filteredPoints.filter { $0.bucketIndex == selectedBucketIndex }.sorted { $0.count > $1.count }
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
                            Text("\(row.count)")
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

    // MARK: - Hidden-series persistence

    private var hiddenSeries: Set<String> {
        Set(decodeNames(mode == .virtues ? hiddenVirtuesRaw : hiddenHabitsRaw))
    }

    private func toggleHidden(_ name: String) {
        var current = decodeNames(mode == .virtues ? hiddenVirtuesRaw : hiddenHabitsRaw)
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
        if mode == .virtues {
            hiddenVirtuesRaw = encoded
        } else {
            hiddenHabitsRaw = encoded
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

    // MARK: - Data

    private var seriesNames: [String] {
        switch mode {
        case .virtues:
            return Array(Set(tasks.flatMap { $0.virtues })).sorted()
        case .habits:
            return Array(Set(tasks.filter { $0.repeatAgain != nil }.map { $0.title })).sorted()
        }
    }

    private var allPoints: [TrendPoint] {
        let names = seriesNames
        guard !names.isEmpty else { return [] }

        var points: [TrendPoint] = []
        for bucket in buckets {
            let inBucket = tasks.filter { t in
                guard t.completed, let d = t.date else { return false }
                return d >= bucket.start && d < bucket.end
            }

            var counts: [String: Int] = [:]
            switch mode {
            case .virtues:
                for t in inBucket {
                    for v in t.virtues { counts[v, default: 0] += 1 }
                }
            case .habits:
                for t in inBucket where t.repeatAgain != nil {
                    counts[t.title, default: 0] += 1
                }
            }

            for name in names {
                points.append(TrendPoint(bucketIndex: bucket.index, seriesName: name, count: counts[name] ?? 0))
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
            let end = bucketEnd(start: start)
            result.append(Bucket(index: -i, start: start, end: end, label: label(for: start)))
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
