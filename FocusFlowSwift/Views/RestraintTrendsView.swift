import SwiftUI
import SwiftData
import Charts

// Timeline chart for restraints, one line per restraint, switchable via a
// segmented control:
//  - "Pass Rate": % of resolved (pass/fail) instances that were a Pass, per
//    bucket. Pending instances don't count either way.
//  - "Overuse": total overusedAmount logged, per bucket. Restraints mix
//    minutes and arbitrary quantity units, so the axis is a generic "Amount"
//    — the selection readout below shows each restraint's real unit.
// Bucketed by Day/Week/Month/Year (default Week), showing the 7 most recent
// buckets with Previous/Next paging 7 buckets at a time. Mirrors
// VirtueHabitTrendsView / ProjectTrendsView's structure and interactions.
struct RestraintTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var restraints: [Restraint]

    enum Mode: String, CaseIterable, Identifiable {
        case passRate = "Pass Rate"
        case overuse = "Overuse"
        var id: String { rawValue }
        // "Pass Rate" reads oddly for Practices — reuse the same passWord
        // wording as the dashboard bars ("Done Rate" vs "Pass Rate").
        func label(for kind: RestraintKind) -> String {
            self == .passRate ? "\(kind.passWord) Rate" : rawValue
        }
    }

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var kindFilter: RestraintKind = .restraint
    @State private var mode: Mode = .passRate
    @State private var granularity: Granularity = .week
    @State private var windowEndAnchor = Date()
    @State private var selectedBucketIndex: Int? = 0

    // Separate persisted chip-selection per kind, so hiding items while
    // looking at Restraints doesn't affect what's shown for Practices.
    @AppStorage("restraintTrends.hiddenRestraints") private var hiddenRestraintsRaw: String = ""
    @AppStorage("restraintTrends.hiddenPractices") private var hiddenPracticesRaw: String = ""
    private var hiddenRaw: String {
        get { kindFilter == .restraint ? hiddenRestraintsRaw : hiddenPracticesRaw }
        nonmutating set {
            // @AppStorage's own setter is nonmutating (its storage lives
            // outside the struct), so this can be too.
            if kindFilter == .restraint { hiddenRestraintsRaw = newValue }
            else { hiddenPracticesRaw = newValue }
        }
    }

    private let calendar = Calendar.current

    struct Bucket: Identifiable {
        let id = Int.random(in: Int.min...Int.max)
        let index: Int
        let start: Date
        let lastDay: Date
        let label: String
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let bucketIndex: Int
        let seriesName: String
        let value: Double
        let unit: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Kind", selection: $kindFilter) {
                        ForEach(RestraintKind.allCases) { k in
                            Text(k.pluralName).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.label(for: kindFilter)).tag(m) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases) { g in Text(g.rawValue).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: granularity) { _, _ in windowEndAnchor = Date() }

                    pagerHeader

                    if seriesNames.isEmpty {
                        Text("No \(kindFilter.pluralName.lowercased()) yet.")
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
            .navigationTitle("Rule Trends")
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
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Name", point.seriesName))
                    .symbol(by: .value("Name", point.seriesName))

                    PointMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value("Value", point.value)
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
            .chartYAxisLabel(mode == .passRate ? "Pass Rate %" : "Amount")
            .frame(height: 260)

            selectionReadout
        }
    }

    @ViewBuilder
    private var selectionReadout: some View {
        if let selectedBucketIndex, let bucket = buckets.first(where: { $0.index == selectedBucketIndex }) {
            let rows = filteredPoints.filter { $0.bucketIndex == selectedBucketIndex }.sorted { $0.value > $1.value }
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
                            Text(mode == .passRate ? "\(Int(row.value.rounded()))%" : "\(fmt(row.value)) \(row.unit)")
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

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
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
        Set(decodeNames(hiddenRaw))
    }

    private func toggleHidden(_ name: String) {
        var current = decodeNames(hiddenRaw)
        if let idx = current.firstIndex(of: name) {
            current.remove(at: idx)
        } else {
            current.append(name)
        }
        hiddenRaw = encodeNames(current)
    }

    private func showAll() { hiddenRaw = encodeNames([]) }
    private func hideAll() { hiddenRaw = encodeNames(seriesNames) }
    private func isolate(_ name: String) { hiddenRaw = encodeNames(seriesNames.filter { $0 != name }) }

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

    private var kindItems: [Restraint] {
        restraints.filter { $0.kind == kindFilter }
    }

    private var seriesNames: [String] {
        kindItems.map { $0.name }.sorted()
    }

    private func unit(for r: Restraint) -> String {
        r.effectiveLimitType == .duration ? "min" : r.quantityUnit
    }

    private var allPoints: [TrendPoint] {
        guard !kindItems.isEmpty else { return [] }
        var points: [TrendPoint] = []

        for bucket in buckets {
            for r in kindItems {
                let recs = r.instances.filter { $0.date >= bucket.start && $0.date <= bucket.lastDay }
                let value: Double
                switch mode {
                case .passRate:
                    let resolved = recs.filter { $0.status == "pass" || $0.status == "fail" }
                    let passed = resolved.filter { $0.status == "pass" }.count
                    value = resolved.isEmpty ? 0 : (Double(passed) / Double(resolved.count)) * 100
                case .overuse:
                    value = recs.reduce(0.0) { $0 + $1.overusedAmount }
                }
                points.append(TrendPoint(bucketIndex: bucket.index, seriesName: r.name, value: value, unit: unit(for: r)))
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
            let weekday = calendar.component(.weekday, from: start)
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
        case .day: formatter.dateFormat = "MMM d"
        case .week: formatter.dateFormat = "MMM d"
        case .month: formatter.dateFormat = "MMM yyyy"
        case .year: formatter.dateFormat = "yyyy"
        }
        return formatter.string(from: start)
    }
}
