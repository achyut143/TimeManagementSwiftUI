import SwiftUI
import Charts

// Bar chart of continuous in-app focus time (FocusSessionTracker). Unlike
// AwayTimeTrendsView (one rolling line across same-sized buckets for every
// granularity), each granularity here groups differently, one calendar
// period per page:
//  - Day:   one bar per session/"iteration" that day (app-foreground span)
//  - Week:  one bar per day of that week (daily totals)
//  - Month: one bar per week of that month (weekly totals)
//  - Year:  one bar per month of that year (monthly totals)
struct FocusTimeTrendsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tracker = FocusSessionTracker.shared

    enum Granularity: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }

    @State private var granularity: Granularity = .day
    @State private var anchorDate = Date()
    @State private var selectedLabel: String? = nil

    private let calendar = Calendar.current

    struct Bar: Identifiable {
        let index: Int
        let label: String
        let seconds: Double
        var id: Int { index }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Granularity", selection: $granularity) {
                        ForEach(Granularity.allCases) { g in Text(g.rawValue).tag(g) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: granularity) { _, _ in selectedLabel = nil }

                    pagerHeader
                    totalReadout
                    chartView
                }
                .padding()
            }
            .navigationTitle("Focus Time Trend")
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
                shiftAnchor(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }

            Spacer()

            Text(pageTitle)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                shiftAnchor(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isAtPresent)
        }
        .buttonStyle(.bordered)
    }

    private var totalReadout: some View {
        let total = bars.reduce(0) { $0 + $1.seconds }
        return HStack {
            Text(totalLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(FocusSessionTracker.formatted(total))
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.mint)
        }
    }

    private var totalLabel: String {
        switch granularity {
        case .day: return "Total today · \(bars.count) session\(bars.count == 1 ? "" : "s")"
        case .week: return "Total this week"
        case .month: return "Total this month"
        case .year: return "Total this year"
        }
    }

    // MARK: - Chart

    private var chartView: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: bars.count > 8) {
                chartBody
                    .frame(width: max(geo.size.width - 32, CGFloat(bars.count) * 52), height: geo.size.height)
            }
        }
        .frame(height: 260)
    }

    private var chartBody: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Period", bar.label),
                    y: .value("Minutes", bar.seconds / 60)
                )
                .foregroundStyle(selectedLabel == bar.label ? Color.mint : Color.mint.opacity(0.65))
                .cornerRadius(4)
            }
        }
        .chartXSelection(value: $selectedLabel)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartYAxisLabel("Minutes Focused")
        .overlay(alignment: .center) {
            if bars.isEmpty {
                Text("No focus time recorded for this period")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    private var bars: [Bar] {
        switch granularity {
        case .day: return dayBars
        case .week: return weekBars
        case .month: return monthBars
        case .year: return yearBars
        }
    }

    private var dayBars: [Bar] {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return tracker.sessions(on: anchorDate).enumerated().map { i, s in
            Bar(index: i, label: fmt.string(from: s.start), seconds: s.seconds)
        }
    }

    private var weekBars: [Bar] {
        let start = weekStart(for: anchorDate)
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d"
        return (0..<7).map { i in
            let day = calendar.date(byAdding: .day, value: i, to: start) ?? start
            return Bar(index: i, label: fmt.string(from: day), seconds: tracker.totalSeconds(on: day))
        }
    }

    private var monthBars: [Bar] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: anchorDate) else { return [] }
        let monthStart = monthInterval.start
        let monthLastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"

        var bars: [Bar] = []
        var weekStartCursor = weekStart(for: monthStart)
        var idx = 0
        while weekStartCursor <= monthLastDay {
            let weekLastDay = calendar.date(byAdding: .day, value: 6, to: weekStartCursor) ?? weekStartCursor
            let clipStart = max(weekStartCursor, monthStart)
            let clipEnd = min(weekLastDay, monthLastDay)
            let seconds = clipStart <= clipEnd ? tracker.totalSeconds(from: clipStart, to: clipEnd) : 0
            bars.append(Bar(index: idx, label: "Wk \(fmt.string(from: weekStartCursor))", seconds: seconds))
            idx += 1
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekStartCursor) else { break }
            weekStartCursor = next
        }
        return bars
    }

    private var yearBars: [Bar] {
        guard let yearInterval = calendar.dateInterval(of: .year, for: anchorDate) else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"

        var bars: [Bar] = []
        var monthStart = yearInterval.start
        var idx = 0
        while monthStart < yearInterval.end {
            guard let monthInterval = calendar.dateInterval(of: .month, for: monthStart) else { break }
            let monthLastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.end
            let seconds = tracker.totalSeconds(from: monthStart, to: monthLastDay)
            bars.append(Bar(index: idx, label: fmt.string(from: monthStart), seconds: seconds))
            idx += 1
            guard let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { break }
            monthStart = next
        }
        return bars
    }

    // MARK: - Bucketing helpers

    private func weekStart(for date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start) ?? start
    }

    private var periodStart: Date {
        switch granularity {
        case .day: return calendar.startOfDay(for: anchorDate)
        case .week: return weekStart(for: anchorDate)
        case .month: return calendar.dateInterval(of: .month, for: anchorDate)?.start ?? anchorDate
        case .year: return calendar.dateInterval(of: .year, for: anchorDate)?.start ?? anchorDate
        }
    }

    private var periodEnd: Date {
        switch granularity {
        case .day: return calendar.date(byAdding: .day, value: 1, to: periodStart) ?? periodStart
        case .week: return calendar.date(byAdding: .day, value: 7, to: periodStart) ?? periodStart
        case .month: return calendar.date(byAdding: .month, value: 1, to: periodStart) ?? periodStart
        case .year: return calendar.date(byAdding: .year, value: 1, to: periodStart) ?? periodStart
        }
    }

    private var isAtPresent: Bool { periodEnd > Date() }

    private func shiftAnchor(by n: Int) {
        switch granularity {
        case .day: anchorDate = calendar.date(byAdding: .day, value: n, to: anchorDate) ?? anchorDate
        case .week: anchorDate = calendar.date(byAdding: .day, value: 7 * n, to: anchorDate) ?? anchorDate
        case .month: anchorDate = calendar.date(byAdding: .month, value: n, to: anchorDate) ?? anchorDate
        case .year: anchorDate = calendar.date(byAdding: .year, value: n, to: anchorDate) ?? anchorDate
        }
        selectedLabel = nil
    }

    private var pageTitle: String {
        let fmt = DateFormatter()
        switch granularity {
        case .day:
            fmt.dateFormat = "EEEE, MMM d"
            return fmt.string(from: anchorDate)
        case .week:
            let start = weekStart(for: anchorDate)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            fmt.dateFormat = "MMM d"
            return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
        case .month:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: anchorDate)
        case .year:
            fmt.dateFormat = "yyyy"
            return fmt.string(from: anchorDate)
        }
    }
}
