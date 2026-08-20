import SwiftUI
import Charts

// Time series of DistractionTracker's daily totals — aggregate across every
// tracked task each day (not broken out per-task, since distracted tasks
// aren't a stable repeating set the way habits are). Two Y-axis modes:
// Time (seconds away) and Count (number of distraction events). Same
// Day/Week/Month/Year + 7-bucket-paging + tap-to-select pattern as the
// other trend charts.
struct DistractionTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tracker = DistractionTracker.shared

    enum Mode: String, CaseIterable, Identifiable {
        case time = "Time"
        case count = "Count"
        var id: String { rawValue }
    }

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .time
    @State private var granularity: Granularity = .week
    @State private var windowEndAnchor = Date()
    @State private var selectedBucketIndex: Int? = 0

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
        let count: Int
        let seconds: Double
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
                    chartView
                }
                .padding()
            }
            .navigationTitle("Distraction Trend")
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

                ForEach(points) { point in
                    let y = mode == .time ? point.seconds / 60 : Double(point.count)
                    LineMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value(mode == .time ? "Minutes" : "Count", y)
                    )
                    .foregroundStyle(.red)
                    .symbol(.circle)

                    PointMark(
                        x: .value("Period", point.bucketIndex),
                        y: .value(mode == .time ? "Minutes" : "Count", y)
                    )
                    .foregroundStyle(.red)
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
            .chartYAxisLabel(mode == .time ? "Minutes" : "Distractions")
            .frame(height: 260)

            selectionReadout
        }
    }

    @ViewBuilder
    private var selectionReadout: some View {
        if let selectedBucketIndex, let bucket = buckets.first(where: { $0.index == selectedBucketIndex }) {
            let point = points.first(where: { $0.bucketIndex == selectedBucketIndex })
            HStack {
                Text(bucket.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(mode == .time ? formattedSeconds(point?.seconds ?? 0) : "\(point?.count ?? 0)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func formattedSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // MARK: - Data

    private var points: [TrendPoint] {
        buckets.map { bucket in
            let (count, seconds) = totalsInBucket(bucket)
            return TrendPoint(bucketIndex: bucket.index, count: count, seconds: seconds)
        }
    }

    private func totalsInBucket(_ bucket: Bucket) -> (Int, Double) {
        var count = 0
        var seconds = 0.0
        var day = bucket.start
        while day <= bucket.lastDay {
            let daily = tracker.dayTotals(date: day)
            count += daily.count
            seconds += daily.seconds
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (count, seconds)
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
