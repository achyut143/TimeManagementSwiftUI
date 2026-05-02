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
    @State private var cachedStatsMap: [String: (streak: Int, best: Int, completed: Int, total: Int)] = [:]
    @State private var cachedStatusGrid: [String: CellStatus] = [:]  // key: "habitName|dateISO"

    private let leftWidth: CGFloat = 170
    private let cellWidth: CGFloat = 44
    private let rowHeight: CGFloat = 52

    // MARK: - Computed (use caches)

    private var habitTasks: [Task] { tasks.filter { ($0 as Task).repeatAgain != nil } }
    private var habitNames: [String] { cachedHabitNames }
    private var dateRange: [Date] { cachedDateRange }

    // MARK: - Helpers

    private enum CellStatus { case completed, missed, noData }

    private func status(habit: String, on date: Date) -> CellStatus {
        let key = "\(habit)|\(date.timeIntervalSince1970)"
        return cachedStatusGrid[key] ?? .noData
    }

    private func stats(habit: String) -> (streak: Int, best: Int, completed: Int, total: Int) {
        cachedStatsMap[habit] ?? (streak: 0, best: 0, completed: 0, total: 0)
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

        // Build task lookup by habit name for fast access
        var tasksByHabit: [String: [Task]] = [:]
        for task in ht {
            tasksByHabit[task.title, default: []].append(task)
        }

        var statsMap: [String: (streak: Int, best: Int, completed: Int, total: Int)] = [:]
        var statusGrid: [String: CellStatus] = [:]

        for habit in names {
            let habitTasks = tasksByHabit[habit] ?? []
            var completions: [(Date, Bool)] = []

            for date in dates {
                let day = habitTasks.filter { cal.isDate($0.date ?? .distantPast, inSameDayAs: date) }
                let key = "\(habit)|\(date.timeIntervalSince1970)"
                if day.isEmpty {
                    statusGrid[key] = .noData
                    continue
                }
                if day.contains(where: { $0.completed }) {
                    statusGrid[key] = .completed
                    completions.append((date, true))
                } else if day.contains(where: { $0.notCompleted }) {
                    statusGrid[key] = .missed
                    completions.append((date, false))
                } else {
                    statusGrid[key] = .noData
                }
            }

            let sorted = completions.sorted { $0.0 < $1.0 }
            var best = 0, tmp = 0
            for (_, done) in sorted { done ? (tmp += 1) : (tmp = 0); best = max(best, tmp) }
            var current = 0
            for (_, done) in sorted.reversed() { if done { current += 1 } else { break } }
            let completedCount = sorted.filter { $0.1 }.count
            statsMap[habit] = (streak: current, best: best, completed: completedCount, total: sorted.count)
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
                // Left column header cell
                Text("Habit")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .frame(width: leftWidth, height: rowHeight, alignment: .leading)
                    .padding(.leading, 12)
                    .background(Color(.systemGroupedBackground))
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 2, y: 0)

                // Date header — fixed frame, content offset inside it to mirror scroll
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
        }
    }

    private var leftColumnDataRows: some View {
        VStack(spacing: 0) {
            ForEach(habitNames, id: \.self) { habit in
                let s = stats(habit: habit)
                VStack(alignment: .leading, spacing: 3) {
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
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green).font(.system(size: 18))
        case .missed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red).font(.system(size: 18))
        case .noData:
            Text("–").font(.caption).foregroundColor(.secondary.opacity(0.4))
        }
    }
}
