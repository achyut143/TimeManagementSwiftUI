import SwiftUI
import SwiftData
import Foundation

struct HabitGridView: View {
    @Query private var tasks: [Task]
    @Binding var fromDate: Date
    @Binding var toDate: Date

    @State private var searchText: String = ""
    @State private var appliedSearch: String = ""

    @State private var pendingFromDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var pendingToDate: Date = Date()
    @State private var appliedFromDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var appliedToDate: Date = Date()

    @State private var showFilters: Bool = false
    @State private var dateScrollOffset: CGFloat = 0

    // MARK: - Caches
    @State private var cachedDateRange: [Date] = []
    @State private var cachedHabitNames: [String] = []
    @State private var cachedStatsMap: [String: GridHabitStats] = [:]
    @State private var cachedStatusGrid: [String: CellStatus] = [:]  // key: "habitName|timeInterval"

    private let leftWidth: CGFloat = 170
    private let cellWidth: CGFloat = 44
    private let rowHeight: CGFloat = 68

    // MARK: - Computed (use caches)

    private var habitTasks: [Task] { tasks.filter { ($0 as Task).repeatAgain != nil } }
    private var habitNames: [String] { cachedHabitNames }
    private var dateRange: [Date] { cachedDateRange }

    // MARK: - Data Types

    private struct GridHabitStats {
        var streak: Int = 0
        var best: Int = 0
        var completed: Int = 0
        var total: Int = 0
        var ideal: Int = 0
        var good: Int = 0
        var survival: Int = 0
        var idle: Int = 0
    }

    // Completion states based on timeSpent / allocatedTime ratio:
    //   ideal    ≥ 75%
    //   good     30–75%
    //   survival 10–30%
    //   idle     < 10% or no time data (backward-compatible default = green)
    private enum CellStatus {
        case completedIdeal
        case completedGood
        case completedSurvival
        case completedIdle
        case missed
        case noData

        var isCompleted: Bool {
            switch self {
            case .completedIdeal, .completedGood, .completedSurvival, .completedIdle: return true
            default: return false
            }
        }
    }

    // MARK: - Helpers

    private func status(habit: String, on date: Date) -> CellStatus {
        let key = "\(habit)|\(date.timeIntervalSince1970)"
        return cachedStatusGrid[key] ?? .noData
    }

    private func stats(habit: String) -> GridHabitStats {
        cachedStatsMap[habit] ?? GridHabitStats()
    }

    /// Determine the completion state for a day's tasks using time ratio.
    /// Falls back to .completedIdle when timeSpent is missing or zero (backward compat).
    private func completionStatus(for dayTasks: [Task]) -> CellStatus {
        guard let completedTask = dayTasks.first(where: { $0.completed }) else {
            return dayTasks.contains(where: { $0.notCompleted }) ? .missed : .noData
        }

        let allocated = completedTask.allocatedTimeInMinutes
        guard let spent = completedTask.timeSpent, spent > 0, allocated > 0 else {
            return .completedIdle
        }

        let ratio = spent / allocated
        if ratio >= 0.75 { return .completedIdeal }
        if ratio >= 0.30 { return .completedGood }
        if ratio >= 0.10 { return .completedSurvival }
        return .completedIdle
    }

    // MARK: - Grid Recomputation

    private func recomputeGrid() {
        let cal = Calendar.current
        var dates: [Date] = []
        var cur = appliedFromDate
        while cur <= appliedToDate {
            dates.append(cur)
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur
        }
        cachedDateRange = dates

        let ht = tasks.filter { $0.repeatAgain != nil }
        var names = Array(Set(ht.map { $0.title })).sorted()
        if !appliedSearch.isEmpty {
            names = names.filter { $0.localizedCaseInsensitiveContains(appliedSearch) }
        }
        cachedHabitNames = names

        var tasksByHabit: [String: [Task]] = [:]
        for task in ht {
            tasksByHabit[task.title, default: []].append(task)
        }

        var statsMap: [String: GridHabitStats] = [:]
        var statusGrid: [String: CellStatus] = [:]

        for habit in names {
            let habitTasks = tasksByHabit[habit] ?? []
            var completions: [(Date, Bool)] = []
            var idealCount = 0, goodCount = 0, survivalCount = 0, idleCount = 0

            for date in dates {
                let day = habitTasks.filter { cal.isDate($0.date ?? .distantPast, inSameDayAs: date) }
                let key = "\(habit)|\(date.timeIntervalSince1970)"
                if day.isEmpty {
                    statusGrid[key] = .noData
                    continue
                }
                let cellStatus = completionStatus(for: day)
                statusGrid[key] = cellStatus
                switch cellStatus {
                case .completedIdeal:
                    completions.append((date, true)); idealCount += 1
                case .completedGood:
                    completions.append((date, true)); goodCount += 1
                case .completedSurvival:
                    completions.append((date, true)); survivalCount += 1
                case .completedIdle:
                    completions.append((date, true)); idleCount += 1
                case .missed:
                    completions.append((date, false))
                case .noData:
                    break
                }
            }

            let sorted = completions.sorted { $0.0 < $1.0 }
            var best = 0, tmp = 0
            for (_, done) in sorted { done ? (tmp += 1) : (tmp = 0); best = max(best, tmp) }
            var current = 0
            for (_, done) in sorted.reversed() { if done { current += 1 } else { break } }
            let completedCount = sorted.filter { $0.1 }.count
            statsMap[habit] = GridHabitStats(
                streak: current, best: best,
                completed: completedCount, total: sorted.count,
                ideal: idealCount, good: goodCount,
                survival: survivalCount, idle: idleCount
            )
        }

        cachedStatsMap = statsMap
        cachedStatusGrid = statusGrid
    }

    private func dateLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let m = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        let abbr = ["J","F","M","A","M","J","J","A","S","O","N","D"]
        return "\(abbr[m-1])\(day)"
    }

    private func isToday(_ d: Date) -> Bool { Calendar.current.isDateInToday(d) }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterPanel
            if habitNames.isEmpty {
                Spacer()
                Text("No habits found").foregroundColor(.secondary)
                Spacer()
            } else {
                gridContent
            }
        }
        .onAppear {
            pendingFromDate = fromDate
            pendingToDate = toDate
            appliedFromDate = fromDate
            appliedToDate = toDate
            recomputeGrid()
        }
        .onChange(of: tasks.count) { _, _ in recomputeGrid() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search habits", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = ""; appliedSearch = ""; recomputeGrid() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))

            Button {
                appliedSearch = searchText
                recomputeGrid()
            } label: {
                Text("Search")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFilters.toggle() }
            } label: {
                Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundColor(.indigo)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var filterPanel: some View {
        Group {
            if showFilters {
                VStack(spacing: 10) {
                    HStack {
                        Text("From").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                        DatePicker("", selection: $pendingFromDate, displayedComponents: .date)
                            .labelsHidden()
                        Spacer()
                    }
                    HStack {
                        Text("To").font(.caption).foregroundColor(.secondary).frame(width: 36, alignment: .leading)
                        DatePicker("", selection: $pendingToDate, displayedComponents: .date)
                            .labelsHidden()
                        Spacer()
                    }
                    Button {
                        appliedFromDate = pendingFromDate
                        appliedToDate = pendingToDate
                        fromDate = pendingFromDate
                        toDate = pendingToDate
                        recomputeGrid()
                        withAnimation(.easeInOut(duration: 0.2)) { showFilters = false }
                    } label: {
                        Text("Apply Filters")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        VStack(spacing: 0) {
            // Sticky header row (outside vertical scroll)
            HStack(spacing: 0) {
                Text("Habit")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: leftWidth, height: rowHeight, alignment: .leading)
                    .padding(.leading, 12)
                    .background(Color(.systemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 2, y: 0)

                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
                    .overlay(alignment: .leading) {
                        dateHeaderRow
                            .offset(x: -dateScrollOffset)
                    }
                    .clipped()
                    .allowsHitTesting(false)
            }
            Divider()

            // Scrollable data rows
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    leftColumnDataRows
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(habitNames, id: \.self) { habit in
                                dateCellRow(habit: habit)
                                Divider().padding(.leading, 4)
                            }
                        }
                    }
                    .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, x in
                        dateScrollOffset = x
                    }
                }
            }

            statsFooter
        }
    }

    private var leftColumnDataRows: some View {
        VStack(spacing: 0) {
            ForEach(habitNames, id: \.self) { habit in
                let s = stats(habit: habit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label("\(s.streak)", systemImage: "flame.fill")
                            .font(.caption2).foregroundColor(.orange)
                        Label("\(s.best)", systemImage: "crown.fill")
                            .font(.caption2).foregroundColor(Color(hue: 0.12, saturation: 0.9, brightness: 0.85))
                        Text("\(s.completed)/\(s.total)")
                            .font(.caption2).fontWeight(.bold).foregroundColor(.primary)
                    }
                    if s.ideal + s.good + s.survival > 0 {
                        HStack(spacing: 5) {
                            if s.ideal > 0 {
                                Text("I:\(s.ideal)").font(.caption2).foregroundColor(.teal)
                            }
                            if s.good > 0 {
                                Text("G:\(s.good)").font(.caption2).foregroundColor(.yellow)
                            }
                            if s.survival > 0 {
                                Text("S:\(s.survival)").font(.caption2).foregroundColor(.orange)
                            }
                        }
                    }
                }
                .frame(width: leftWidth, height: rowHeight, alignment: .leading)
                .padding(.leading, 12)
                .background(Color(.systemBackground))
                Divider().padding(.leading, 4)
            }
        }
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.06), radius: 3, x: 2, y: 0)
    }

    private var dateHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(dateRange.reversed()), id: \.self) { date in
                Text(dateLabel(date))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(isToday(date) ? .blue : .secondary)
                    .fontWeight(isToday(date) ? .bold : .regular)
                    .frame(width: cellWidth, height: rowHeight)
                    .background(isToday(date) ? Color.blue.opacity(0.06) : Color(.systemGroupedBackground))
            }
        }
    }

    private func dateCellRow(habit: String) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(dateRange.reversed()), id: \.self) { date in
                let s = status(habit: habit, on: date)
                cellView(s)
                    .frame(width: cellWidth, height: rowHeight)
                    .background(isToday(date) ? Color.blue.opacity(0.04) : Color.clear)
            }
        }
    }

    @ViewBuilder
    private func cellView(_ s: CellStatus) -> some View {
        switch s {
        case .completedIdeal:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.teal).font(.system(size: 18))
        case .completedGood:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.yellow).font(.system(size: 18))
        case .completedSurvival:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.orange).font(.system(size: 18))
        case .completedIdle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green).font(.system(size: 18))
        case .missed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red).font(.system(size: 18))
        case .noData:
            Text("–").font(.caption).foregroundColor(.secondary.opacity(0.4))
        }
    }

    // MARK: - Stats Footer

    private var statsFooter: some View {
        let totals = habitNames.reduce((ideal: 0, good: 0, survival: 0, idle: 0)) { acc, habit in
            let s = stats(habit: habit)
            return (acc.ideal + s.ideal, acc.good + s.good, acc.survival + s.survival, acc.idle + s.idle)
        }

        return VStack(spacing: 6) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.teal).frame(width: 8, height: 8)
                        Text("Ideal (≥75%)").font(.caption2).foregroundColor(.secondary)
                        Text("\(totals.ideal)").font(.caption2).fontWeight(.bold).foregroundColor(.teal)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.yellow).frame(width: 8, height: 8)
                        Text("Good (30-75%)").font(.caption2).foregroundColor(.secondary)
                        Text("\(totals.good)").font(.caption2).fontWeight(.bold).foregroundColor(.yellow)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 8, height: 8)
                        Text("Survival (10-30%)").font(.caption2).foregroundColor(.secondary)
                        Text("\(totals.survival)").font(.caption2).fontWeight(.bold).foregroundColor(.orange)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Idle (no time data)").font(.caption2).foregroundColor(.secondary)
                        Text("\(totals.idle)").font(.caption2).fontWeight(.bold).foregroundColor(.green)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
}
