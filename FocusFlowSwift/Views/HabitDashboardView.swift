import SwiftUI
import SwiftData
import Foundation
import Charts

struct HabitDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var eventDays: [EventDay]
    @State private var selectedHabit = ""
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var pendingFromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var pendingToDate = Date()
    @State private var filterMode = "all"
    
    private static let startDateKey = "HabitDashboardStartDate"
    @State private var showDeleteConfirmation = false
    @State private var showArchiveConfirmation = false
    @State private var showArchivedHabits = false
    @State private var habitToDelete = ""
    @State private var searchText = ""
    @State private var appliedSearch = ""
    @State private var cachedTabStats: [String: HabitStats] = [:]
    @State private var showEventDetail = false
    @State private var selectedEventDate: Date?
    @State private var selectedEventDay: EventDay?
    @State private var habitVisualization: HabitVisualization = .calendar
    @State private var chartGranularity: ChartGranularity = .range
    @State private var chartYear: Int = Calendar.current.component(.year, from: Date())

    var initialHabit: String? = nil
    
    init(initialHabit: String? = nil) {
        self.initialHabit = initialHabit
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
            headerView
            
            // Overall streak summary
            if !filteredHabitNames.isEmpty {
                overallStreakSummary
            }
            
            dateFilters
                HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search habits…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    appliedSearch = searchText
                } label: {
                    Text("Search")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                }
                if !appliedSearch.isEmpty {
                    Button { searchText = ""; appliedSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            
    if filteredHabitNames.isEmpty {
        Text("No habits match “\(searchText)”")
          .foregroundColor(.secondary)
          .padding(.vertical, 20)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 12) {
            ForEach(filteredHabitNames, id: \.self) { habitName in
              habitTabView(habitName: habitName)
                .id("\(habitName)-\(fromDate)-\(toDate)-\(filterMode)")
            }
          }
          .padding(.horizontal)
        }
      }

      // 3. The rest of your content shows only if there’s a selected habit
    if !selectedHabit.isEmpty {
    visualizationPicker
    if habitVisualization == .calendar {
        habitCalendar
    } else {
        habitBarChartView
    }
    statsView
} else {
    emptyStateView
}
            }
            .padding(.bottom, 20) // Add bottom padding for better scrolling
        }
        .navigationTitle("Habit Tracker")
        .toolbar {
            }
    .onAppear {
      loadStartDate()
      if let initialHabit = initialHabit, filteredHabitNames.contains(initialHabit) {
        selectedHabit = initialHabit
      } else if selectedHabit.isEmpty, let first = filteredHabitNames.first {
        selectedHabit = first
      }
    }
    .onChange(of: fromDate) { _, _ in recomputeTabStats() }
    .onChange(of: toDate) { _, _ in recomputeTabStats() }
    .onChange(of: tasks.count) { _, _ in recomputeTabStats() }
    .onChange(of: filteredHabitNames) { _, newList in
      // Reset selectedHabit if it was filtered out
      if !newList.contains(selectedHabit) {
        selectedHabit = newList.first ?? ""
      }
    }

        .alert("Habit Actions", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Archive", action: {
                archiveHabit(habitToDelete)
            })
            Button("Delete", role: .destructive) {
                deleteHabit(habitToDelete)
            }
        } message: {
            Text("Choose an action for this habit:\n\n• Archive: Save statistics and remove from active habits\n• Delete: Permanently remove habit and all its tasks")
        }
        .sheet(isPresented: $showArchivedHabits) {
            ArchivedHabitsView()
        }
        .sheet(isPresented: $showEventDetail) {
            if let selectedDate = selectedEventDate {
                EventDetailView(date: selectedDate, eventDay: selectedEventDay)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Habit Tracker")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button {
                showArchivedHabits = true
            } label: {
                Image(systemName: "archivebox")
                    .font(.title3)
                    .foregroundColor(.blue)
            }
            
            Picker("Filter", selection: $filterMode) {
                Text("All").tag("all")
                Text("Routines").tag("routines")
                Text("Repeats").tag("repeats")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding()
    }
    
    private var dateFilters: some View {
        VStack(spacing: 8) {
            DateRangeShiftControl(start: $pendingFromDate, end: $pendingToDate, onShift: {
                fromDate = pendingFromDate
                toDate = pendingToDate
                saveStartDate()
            })
            DatePicker("Start Date", selection: $pendingFromDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker("End Date", selection: $pendingToDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            Button {
                fromDate = pendingFromDate
                toDate = pendingToDate
                saveStartDate()
            } label: {
                Text("Apply Dates")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal)
    }
    
    private func saveStartDate() {
        UserDefaults.standard.set(fromDate, forKey: Self.startDateKey)
    }
    
    private func loadStartDate() {
        if let savedDate = UserDefaults.standard.object(forKey: Self.startDateKey) as? Date {
            fromDate = savedDate
            pendingFromDate = savedDate
        }
        toDate = Date()
        pendingToDate = Date()
        recomputeTabStats()
    }

    private func recomputeTabStats() {
        var result: [String: HabitStats] = [:]
        for name in filteredHabitNames {
            result[name] = calculateStatsForHabit(name)
        }
        cachedTabStats = result
    }
    
   private var filteredHabitNames: [String] {
    // If initialHabit is set, only show that habit
    if let initialHabit = initialHabit, habitNames.contains(initialHabit) {
      return [initialHabit]
    }
    
    return habitNames
      .filter { name in
        switch filterMode {
          case "routines": return name.lowercased().contains("routine")
          case "repeats":  return !name.lowercased().contains("routine")
          default:         return true
        }
      }
      .filter { appliedSearch.isEmpty || $0.localizedCaseInsensitiveContains(appliedSearch) }
  }

  private var habitTabs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(filteredHabitNames, id: \.self) { habitName in
          habitTabView(habitName: habitName)
            .id("\(habitName)-\(fromDate)-\(toDate)-\(filterMode)")
        }
      }
      .padding(.horizontal)
    }
  }

 
    
    private func habitTabView(habitName: String) -> some View {
        let stats = cachedTabStats[habitName] ?? calculateStatsForHabit(habitName)
        let isSelected = selectedHabit == habitName
        
        return VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(habitName.lowercased().contains("routine") ? .purple : .blue)
                    .frame(width: 8, height: 8)
                
                Text(habitName)
                    .font(.caption)
                    .lineLimit(1)
                
                Button(action: { 
                    habitToDelete = habitName
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            
            Text("\(stats.completed)/\(stats.total) (\(Int(stats.percentage))%)")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.green.opacity(0.2))
                .cornerRadius(8)
            
            // Add streak info
            if stats.currentStreak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("\(stats.currentStreak)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(8)
        .background(isSelected ? .blue.opacity(0.2) : .gray.opacity(0.1))
        .cornerRadius(8)
        .onTapGesture {
            selectedHabit = habitName
        }
    }
    
    private var habitCalendar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 4) {
            ForEach(activeDates, id: \.self) { date in
                habitDayView(date: date)
            }
        }
        .padding()
    }

    private var visualizationPicker: some View {
        Picker("Visualization", selection: $habitVisualization) {
            ForEach(HabitVisualization.allCases, id: \.self) { viz in
                Text(viz.rawValue).tag(viz)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var habitBarChartView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Granularity", selection: $chartGranularity) {
                    ForEach(ChartGranularity.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if chartGranularity != .range {
                    Spacer()
                    yearSelector
                }
            }

            Chart {
                ForEach(barChartSegments) { segment in
                    BarMark(
                        x: .value("Tasks", segment.count),
                        y: .value("Period", segment.periodLabel)
                    )
                    .foregroundStyle(by: .value("Status", segment.status))
                    .annotation(position: .overlay) {
                        if segment.count > 0 {
                            Text("\(segment.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                ForEach(barChartData, id: \.periodLabel) { entry in
                    if entry.total > 0 {
                        PointMark(
                            x: .value("Tasks", entry.total),
                            y: .value("Period", entry.periodLabel)
                        )
                        .opacity(0)
                        .annotation(position: .trailing) {
                            Text("\(entry.total)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: ["Completed", "Missed"], range: [Color.green, Color.red.opacity(0.55)])
            .chartYScale(domain: barChartData.map(\.periodLabel))
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                }
            }
            .chartLegend(position: .bottom)
            .frame(height: barChartHeight)
        }
        .padding(.horizontal)
    }

    private var yearSelector: some View {
        HStack(spacing: 8) {
            Button { chartYear -= 1 } label: {
                Image(systemName: "chevron.left")
            }
            Text(String(chartYear))
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44)
            Button { chartYear += 1 } label: {
                Image(systemName: "chevron.right")
            }
        }
        .buttonStyle(.bordered)
    }

    private var barChartHeight: CGFloat {
        let rowHeight: CGFloat = chartGranularity == .weekly ? 16 : 28
        return max(120, CGFloat(barChartData.count) * rowHeight + 40)
    }
    
    private func habitDayView(date: Date) -> some View {
        let status = getStatusForDay(date: date)
        let eventDay = eventDays.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        let eventTypes = eventDay?.eventTypes ?? []
        
        return ZStack {
            // The habit cell content
            VStack(spacing: 2) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(DateFormatter.shortMonth.string(from: date))
                    .font(.caption2)
                
                Text(DateFormatter.weekday.string(from: date))
                    .font(.caption2)
            }
            .frame(width: 40, height: 40)
            .background(colorForStatus(status))
            .foregroundColor(status == .noData || status == .completedGood ? .primary : .white)
            .cornerRadius(6)
            
            // Event day halos - circular glowing rings with gaps
            if !eventTypes.isEmpty {
                Button(action: {
                    selectedEventDate = date
                    selectedEventDay = eventDay
                    showEventDetail = true
                }) {
                    ZStack {
                        // Primary halo - innermost ring with gap
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        eventTypes[0].color.opacity(0.8),
                                        eventTypes[0].color.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 52, height: 52)
                            .shadow(color: eventTypes[0].color.opacity(0.6), radius: 3, x: 0, y: 0)
                            .shadow(color: eventTypes[0].color.opacity(0.4), radius: 6, x: 0, y: 0)
                        
                        // Secondary halo - middle ring
                        if eventTypes.count > 1 {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            eventTypes[1].color.opacity(0.7),
                                            eventTypes[1].color.opacity(0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 58, height: 58)
                                .shadow(color: eventTypes[1].color.opacity(0.5), radius: 4, x: 0, y: 0)
                        }
                        
                        // Tertiary halo - outermost ring
                        if eventTypes.count > 2 {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            eventTypes[2].color.opacity(0.6),
                                            eventTypes[2].color.opacity(0.2)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                                .frame(width: 64, height: 64)
                                .shadow(color: eventTypes[2].color.opacity(0.4), radius: 5, x: 0, y: 0)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var statsView: some View {
        let stats = calculateStatsForHabit(selectedHabit)
        let timeStats = calculateTimeStatsForHabit(selectedHabit)
        let totalCompleted = stats.completed
        let completionRate = stats.total > 0 ? Int(Double(stats.completed) / Double(stats.total) * 100) : 0

        func pct(_ n: Int) -> String {
            totalCompleted > 0 ? "\(Int(Double(n) / Double(totalCompleted) * 100))%" : "–"
        }

        return VStack(spacing: 10) {
            // Time-state breakdown table
            VStack(spacing: 0) {
                HStack {
                    Text("State").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Times").frame(width: 52, alignment: .trailing)
                    Text("% of Done").frame(width: 72, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(.systemGray6))

                Divider()
                timeStatRow("Ideal (≥75%)", color: .teal, count: timeStats.ideal, pct: pct(timeStats.ideal))
                Divider().padding(.leading, 14)
                timeStatRow("Good (30–75%)", color: Color(hue: 0.14, saturation: 0.85, brightness: 0.90), count: timeStats.good, pct: pct(timeStats.good))
                Divider().padding(.leading, 14)
                timeStatRow("Survival (10–30%)", color: .orange, count: timeStats.survival, pct: pct(timeStats.survival))
                Divider().padding(.leading, 14)
                timeStatRow("Idle (no time data)", color: .green, count: timeStats.idle, pct: pct(timeStats.idle))
                Divider()

                HStack {
                    Text("Total Completed")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(totalCompleted)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.primary)
                        .frame(width: 52, alignment: .trailing)
                    Text("\(completionRate)% rate")
                        .font(.caption.weight(.bold))
                        .foregroundColor(completionRate >= 80 ? .green : completionRate >= 60 ? .orange : .red)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.systemGray6).opacity(0.6))
            }
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))

            // Streaks row
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill").foregroundColor(.orange)
                    VStack(spacing: 2) {
                        Text("\(stats.currentStreak)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.orange)
                        Text("Current Streak")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 0.5, height: 44)

                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill").foregroundColor(.purple)
                    VStack(spacing: 2) {
                        Text("\(stats.maxStreak)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.purple)
                        Text("Max Streak")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func timeStatRow(_ label: String, color: Color, count: Int, pct: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label).font(.caption).foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundColor(count > 0 ? color : .secondary)
                .frame(width: 52, alignment: .trailing)
            Text(pct)
                .font(.caption)
                .foregroundColor(count > 0 ? .primary : .secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
    
    private var overallStreakSummary: some View {
        let allStats = filteredHabitNames.compactMap { cachedTabStats[$0] }
        var totalCurrentStreak = 0, maxStreakOverall = 0, activeStreaks = 0
        for s in allStats {
            totalCurrentStreak += s.currentStreak
            if s.maxStreak > maxStreakOverall { maxStreakOverall = s.maxStreak }
            if s.currentStreak > 0 { activeStreaks += 1 }
        }
        
        return HStack(spacing: 20) {
            VStack {
                Text("\(activeStreaks)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("Active Streaks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack {
                Text("\(totalCurrentStreak)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                Text("Total Current")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack {
                Text("\(maxStreakOverall)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
                Text("Best Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Repeating Tasks")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create tasks with repeat intervals to track habits")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var habitTasks: [Task] {
        tasks.filter { $0.repeatAgain != nil }
    }
    
    private var filteredHabitTasks: [Task] {
        habitTasks.filter { task in
            switch filterMode {
            case "routines":
                return task.title.lowercased().contains("routine")
            case "repeats":
                return !task.title.lowercased().contains("routine")
            default:
                return true
            }
        }
    }
    
   private var habitNames: [String] {
    Array(Set(
      tasks.filter { $0.repeatAgain != nil }
           .map { $0.title }
    ))
    .sorted()
  }
    
    private var dateRange: [Date] {
        var dates: [Date] = []
        var currentDate = fromDate
        
        while currentDate <= toDate {
            dates.append(currentDate)
            currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        return dates
    }
    
    private var activeDates: [Date] {
        dateRange.filter { date in
            let dayTasks = filteredHabitTasks.filter { task in
                task.title == selectedHabit &&
                Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
            }
            return !dayTasks.isEmpty && (dayTasks.contains(where: { $0.completed || $0.notCompleted }))
        }
    }

    // MARK: - Bar Chart Data

    private var barChartData: [HabitBarChartEntry] {
        guard !selectedHabit.isEmpty else { return [] }
        let cal = Calendar.current

        switch chartGranularity {
        case .range:
            let start = cal.startOfDay(for: fromDate)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: toDate)) ?? toDate
            let counts = taskCounts(for: selectedHabit, in: DateInterval(start: start, end: max(start, end)))
            let label = "\(DateFormatter.shortMonth.string(from: fromDate)) \(cal.component(.day, from: fromDate))–\(DateFormatter.shortMonth.string(from: toDate)) \(cal.component(.day, from: toDate))"
            return [HabitBarChartEntry(periodLabel: label, completed: counts.completed, missed: counts.missed)]

        case .monthly:
            return (1...12).compactMap { month in
                guard let monthStart = cal.date(from: DateComponents(year: chartYear, month: month, day: 1)),
                      let interval = cal.dateInterval(of: .month, for: monthStart) else { return nil }
                let counts = taskCounts(for: selectedHabit, in: interval)
                let label = DateFormatter.shortMonth.string(from: monthStart)
                return HabitBarChartEntry(periodLabel: label, completed: counts.completed, missed: counts.missed)
            }

        case .weekly:
            guard let yearStart = cal.date(from: DateComponents(year: chartYear, month: 1, day: 1)),
                  let yearEnd = cal.date(from: DateComponents(year: chartYear, month: 12, day: 31)) else { return [] }
            var entries: [HabitBarChartEntry] = []
            var weekStart = cal.dateInterval(of: .weekOfYear, for: yearStart)?.start ?? yearStart
            while weekStart <= yearEnd {
                let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let counts = taskCounts(for: selectedHabit, in: DateInterval(start: weekStart, end: weekEnd))
                let label = DateFormatter.monthDay.string(from: weekStart)
                entries.append(HabitBarChartEntry(periodLabel: label, completed: counts.completed, missed: counts.missed))
                weekStart = weekEnd
            }
            return entries
        }
    }

    private var barChartSegments: [HabitBarSegment] {
        barChartData.flatMap { entry in
            [
                HabitBarSegment(periodLabel: entry.periodLabel, status: "Completed", count: entry.completed),
                HabitBarSegment(periodLabel: entry.periodLabel, status: "Missed", count: entry.missed)
            ]
        }
    }

    private func taskCounts(for habitName: String, in interval: DateInterval) -> (completed: Int, missed: Int) {
        let cal = Calendar.current
        let habitSpecificTasks = tasks.filter { task in
            guard task.repeatAgain != nil && task.title == habitName else { return false }
            switch filterMode {
            case "routines": return task.title.lowercased().contains("routine")
            case "repeats":  return !task.title.lowercased().contains("routine")
            default:         return true
            }
        }

        var completed = 0
        var missed = 0
        var current = cal.startOfDay(for: interval.start)
        let end = interval.end
        while current < end {
            let dayTasks = habitSpecificTasks.filter { cal.isDate($0.date ?? Date(), inSameDayAs: current) }
            if !dayTasks.isEmpty {
                if dayTasks.contains(where: { $0.completed }) {
                    completed += 1
                } else if dayTasks.contains(where: { $0.notCompleted }) {
                    missed += 1
                }
            }
            current = cal.date(byAdding: .day, value: 1, to: current) ?? end
        }
        return (completed, missed)
    }

    // MARK: - Helper Methods
    
    private func completionStatusForTasks(_ tasks: [Task]) -> HabitStatus {
        guard let completedTask = tasks.first(where: { $0.completed }) else {
            return tasks.contains(where: { $0.notCompleted }) ? .missed : .noData
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

    private func getStatusForDay(date: Date) -> HabitStatus {
        let dayTasks = filteredHabitTasks.filter { task in
            task.title == selectedHabit &&
            Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
        }
        if dayTasks.isEmpty { return .noData }
        return completionStatusForTasks(dayTasks)
    }

    private func colorForStatus(_ status: HabitStatus) -> Color {
        switch status {
        case .completedIdeal:    return .teal
        case .completedGood:     return Color(hue: 0.14, saturation: 0.85, brightness: 0.90)
        case .completedSurvival: return .orange
        case .completedIdle:     return .green
        case .missed:            return .red
        case .noData:            return .gray.opacity(0.3)
        }
    }
    
    // Fixed stats calculation method for individual habits
    private func calculateStatsForHabit(_ habitName: String) -> HabitStats {
        var completed = 0
        var missed = 0
        
        // Get tasks for this specific habit with proper filtering
        let habitSpecificTasks = tasks.filter { task in
            guard task.repeatAgain != nil && task.title == habitName else { return false }
            
            // Apply filter mode
            switch filterMode {
            case "routines":
                return task.title.lowercased().contains("routine")
            case "repeats":
                return !task.title.lowercased().contains("routine")
            default:
                return true
            }
        }
        
        // Create array to track daily completion status for streak calculation
        var dailyCompletions: [(Date, Bool)] = []
        
        // Calculate stats for each date in range
        for date in dateRange {
            let dayTasks = habitSpecificTasks.filter { task in
                Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
            }
            
            if !dayTasks.isEmpty {
                let isCompleted = dayTasks.contains(where: { $0.completed })
                let isMissed = dayTasks.contains(where: { $0.notCompleted })
                
                if isCompleted {
                    completed += 1
                    dailyCompletions.append((date, true))
                } else if isMissed {
                    missed += 1
                    dailyCompletions.append((date, false))
                }
            }
        }
        
        // Calculate streaks
        let streaks = calculateStreaks(from: dailyCompletions)
        
        let total = completed + missed
        let percentage = total > 0 ? Double(completed) / Double(total) * 100 : 0
        
        return HabitStats(
            completed: completed,
            missed: missed,
            noData: 0,
            total: total,
            percentage: percentage,
            currentStreak: streaks.current,
            maxStreak: streaks.max,
            habitName: selectedHabit
        )
    }
    
    private func calculateTimeStatsForHabit(_ habitName: String) -> (ideal: Int, good: Int, survival: Int, idle: Int) {
        let cal = Calendar.current
        let habitSpecificTasks = filteredHabitTasks.filter { $0.title == habitName }
        let tasksByDay = Dictionary(grouping: habitSpecificTasks) { cal.startOfDay(for: $0.date ?? Date()) }

        var ideal = 0, good = 0, survival = 0, idle = 0
        for date in dateRange {
            let day = cal.startOfDay(for: date)
            guard let dayTasks = tasksByDay[day], !dayTasks.isEmpty else { continue }
            switch completionStatusForTasks(dayTasks) {
            case .completedIdeal:    ideal += 1
            case .completedGood:     good += 1
            case .completedSurvival: survival += 1
            case .completedIdle:     idle += 1
            default: break
            }
        }
        return (ideal: ideal, good: good, survival: survival, idle: idle)
    }

    // Helper method to calculate current and max streaks
    private func calculateStreaks(from dailyCompletions: [(Date, Bool)]) -> (current: Int, max: Int) {
        guard !dailyCompletions.isEmpty else { return (0, 0) }
        
        // Sort by date to ensure proper order
        let sortedCompletions = dailyCompletions.sorted { $0.0 < $1.0 }
        
        var currentStreak = 0
        var maxStreak = 0
        var tempStreak = 0
        
        // Calculate streaks by going through sorted completions
        for (_, isCompleted) in sortedCompletions {
            if isCompleted {
                tempStreak += 1
                maxStreak = max(maxStreak, tempStreak)
            } else {
                tempStreak = 0
            }
        }
        
        // Calculate current streak by going backwards from the most recent date
        let reversedCompletions = sortedCompletions.reversed()
        for (_, isCompleted) in reversedCompletions {
            if isCompleted {
                currentStreak += 1
            } else {
                break
            }
        }
        
        return (currentStreak, maxStreak)
    }
    
    private func archiveHabit(_ habitName: String) {
        // Create archived habit with comprehensive statistics
        if let archivedHabit = HabitArchiveService.archiveHabit(habitName: habitName, tasks: tasks, context: modelContext) {
            // Insert the archived habit into the database
            modelContext.insert(archivedHabit)
            
            // Delete the original habit tasks
            let tasksToDelete = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }
            for task in tasksToDelete {
                modelContext.delete(task)
            }
            
            try? modelContext.save()
            
            // Update selected habit if needed
            if selectedHabit == habitName {
                selectedHabit = habitNames.first { $0 != habitName } ?? ""
            }
            
            print("✅ Habit '\(habitName)' archived successfully with \(archivedHabit.totalCompletedDays) completed days and \(archivedHabit.formattedCompletionPercentage) completion rate")
        }
    }
    
    private func deleteHabit(_ habitName: String) {
        let tasksToDelete = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        try? modelContext.save()
        
        if selectedHabit == habitName {
            selectedHabit = habitNames.first { $0 != habitName } ?? ""
        }
    }
}

enum HabitStatus {
    case completedIdeal    // ≥75% time ratio
    case completedGood     // 30–75% time ratio
    case completedSurvival // 10–30% time ratio
    case completedIdle     // no time data or <10% (backward-compat default)
    case missed
    case noData

    var isCompleted: Bool {
        switch self {
        case .completedIdeal, .completedGood, .completedSurvival, .completedIdle: return true
        default: return false
        }
    }
}

struct HabitStats {
    let completed: Int
    let missed: Int
    let noData: Int
    let total: Int
    let percentage: Double
    let currentStreak: Int
    let maxStreak: Int
    let habitName: String?
}

enum HabitVisualization: String, CaseIterable {
    case calendar = "Calendar"
    case barChart = "Bar Chart"
}

enum ChartGranularity: String, CaseIterable {
    case range = "Range"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

struct HabitBarChartEntry {
    let periodLabel: String
    let completed: Int
    let missed: Int
    var total: Int { completed + missed }
}

struct HabitBarSegment: Identifiable {
    let id = UUID()
    let periodLabel: String
    let status: String
    let count: Int
}

extension DateFormatter {
    static let shortMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

#Preview {
    HabitDashboardView()
        .modelContainer(for: [Task.self], inMemory: true)
}
