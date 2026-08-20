import SwiftUI
import SwiftData
import Foundation
import Charts

struct HabitOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @Query private var eventDays: [EventDay]
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var pendingFromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var pendingToDate = Date()
    @State private var selectedView = "chart"  // "chart" | "table" | "all" | "time"
    @State private var timeChartSortOrder: String = "desc"
    @State private var filterMode = "all"
    @State private var multiSearchText: String = ""
    @State private var appliedMultiSearch: String = ""
    @State private var chartSortOrder: String = "none"
    @State private var savedSearches: [SavedSearch] = []
    @State private var saveSearchName: String = ""
    @State private var showSaveSearchField: Bool = false
    @State private var showSearchSuggestions: Bool = false
    @State private var selectedHabit: String? = nil
    @State private var showDetailedView = false
    @State private var showDMSGuide = false
    @State private var showFilters = false
    @State private var selectedRepeatFilter: Int? = nil
    @State private var selectedTagsFilter: Set<String> = []
    @State private var percentageFilter: String = "all" // "all", "above", "below"
    @State private var habitSettings: HabitSettings?
    @State private var showShareSheet = false
    @State private var pdfURL: URL?
    @State private var showNoNotesAlert = false
    @State private var noNotesHabitName = ""
    @State private var showVirtueHabitTrends = false

    // MARK: - Performance caches (populated by recomputeAllStats)
    @State private var cachedStats: [String: HabitStats] = [:]
    @State private var cachedPoints: [String: (earned: Double, allocated: Double)] = [:]
    @State private var cachedDiscipline: [String: DisciplineMuscleScore] = [:]
    @State private var cachedEventStats: [String: (eventDays: Int, nonEventMisses: Int)] = [:]
    @State private var cachedRepeatInterval: [String: Int] = [:]
    @State private var cachedDateRange: [Date] = []
    @State private var cachedHabitTags: [String] = []
    @State private var cachedHabitCountPerTag: [String: Int] = [:]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with filters
                headerView
                
                if selectedView == "chart" {
                    if filteredHabitNames.isEmpty {
                        emptyStateView
                    } else {
                        habitOverviewChartView
                    }
                } else if selectedView == "table" {
                    HabitGridView(fromDate: $fromDate, toDate: $toDate)
                } else if selectedView == "time" {
                    habitOverviewTimeChartView
                } else {
                    // Overall Discipline Level Display (only when discipline filter is selected)
                    if filterMode == "discipline" && !filteredHabitNames.isEmpty {
                        overallDisciplineView
                    }

                    if filteredHabitNames.isEmpty {
                        emptyStateView
                    } else {
                        habitTableView
                    }
                }
            }
            .navigationTitle("Habit Overview")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showVirtueHabitTrends = true
                    } label: {
                        Image(systemName: "chart.xyaxis.line")
                    }
                }
            }
            .onAppear {
                loadHabitSettings()
            }
            .onChange(of: fromDate) { _, _ in recomputeAllStats() }
            .onChange(of: toDate) { _, _ in recomputeAllStats() }
            .onChange(of: tasks.count) { _, _ in recomputeAllStats() }
            .sheet(isPresented: $showDetailedView) {
                if let selectedHabit = selectedHabit {
                    NavigationStack {
                        HabitDashboardView(initialHabit: selectedHabit)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Done") {
                                        showDetailedView = false
                                    }
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let pdfURL = pdfURL {
                    ShareSheet(items: [pdfURL])
                }
            }
            .sheet(isPresented: $showVirtueHabitTrends) {
                VirtueHabitTrendsView()
            }
            .alert("No Notes Available", isPresented: $showNoNotesAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There are no notes for \(noNotesHabitName) in the selected date range.")
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            // Filter controls
            HStack {
                Picker("View", selection: $selectedView) {
                    Text("Chart").tag("chart")
                    Text("Table").tag("table")
                    Text("Time").tag("time")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented)

                Spacer()
            }
            .padding(.horizontal)

            // Filters Accordion (shared between both views)
            filtersAccordion
        }
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }
    
    private var habitTableView: some View {
        VStack(spacing: 0) {
            habitTableHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredHabitNames, id: \.self) { habitName in
                        habitCardView(habitName: habitName)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
    }

    private var habitOverviewChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Completed vs Total by Habit")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Sort by success:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach([("none", "Default"), ("desc", "High → Low"), ("asc", "Low → High")], id: \.0) { value, label in
                        let isSelected = chartSortOrder == value
                        Button(action: { chartSortOrder = value }) {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.blue : Color(.systemGray6)))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Chart {
                    ForEach(overviewBarChartSegments) { segment in
                        BarMark(
                            x: .value("Tasks", segment.count),
                            y: .value("Habit", segment.label)
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
                    ForEach(overviewBarChartEntries) { entry in
                        if entry.total > 0 {
                            PointMark(
                                x: .value("Tasks", entry.total),
                                y: .value("Habit", entry.label)
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
                .chartYScale(domain: overviewBarChartEntries.map(\.label))
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .chartLegend(position: .bottom)
                .frame(height: max(340, CGFloat(overviewBarChartEntries.count) * 56))
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
    }

    private var habitOverviewTimeChartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Spent vs Elapsed by Task")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                    if !timeChartEntries.isEmpty {
                        Text("\(timeChartEntries.count) tasks")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Sort:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach([("none", "Default"), ("desc", "High → Low"), ("asc", "Low → High")], id: \.0) { value, label in
                        let isSelected = timeChartSortOrder == value
                        Button(action: { timeChartSortOrder = value }) {
                            Text(label)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? Color.green : Color(.systemGray6)))
                                .foregroundColor(isSelected ? .white : .primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal)
            }

            if timeChartEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 44))
                        .foregroundColor(.gray)
                    Text("No Time Data")
                        .font(.title3.weight(.semibold))
                    Text("Tasks need elapsed time or recorded time spent in the selected date range")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Chart {
                        ForEach(timeChartSegments) { segment in
                            BarMark(
                                x: .value("Minutes", segment.minutes),
                                y: .value("Task", segment.label)
                            )
                            .foregroundStyle(by: .value("Status", segment.status))
                            .annotation(position: .overlay) {
                                if segment.minutes >= 1 {
                                    Text(formatMinutes(segment.minutes))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        ForEach(timeChartEntries) { entry in
                            if entry.elapsed > 0 {
                                PointMark(
                                    x: .value("Minutes", entry.elapsed),
                                    y: .value("Task", entry.label)
                                )
                                .opacity(0)
                                .annotation(position: .trailing) {
                                    Text(formatMinutes(entry.elapsed))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: ["Spent", "Remaining"], range: [Color.green, Color.red.opacity(0.55)])
                    .chartYScale(domain: timeChartEntries.map(\.label))
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom)
                    }
                    .chartLegend(position: .bottom)
                    .frame(height: max(340, CGFloat(timeChartEntries.count) * 56))
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var habitTableHeader: some View {
        HStack(spacing: 6) {
            Text("Habit")
                .frame(maxWidth: .infinity, alignment: .leading)

            if filterMode == "discipline" {
                Text("DMS").frame(maxWidth: .infinity)
                Text("Done").frame(maxWidth: .infinity)
                Text("Penalty").frame(maxWidth: .infinity)
                Text("Streak").frame(maxWidth: .infinity)
                Text("Bonus").frame(maxWidth: .infinity)
            } else {
                Text("%").frame(maxWidth: .infinity)
                Text("Score").frame(maxWidth: .infinity)
                Text("Streak").frame(maxWidth: .infinity)
                Text("Best").frame(maxWidth: .infinity)
                Text("Points").frame(maxWidth: .infinity)
                Text("Events").frame(maxWidth: .infinity)
                Text("Misses").frame(maxWidth: .infinity)
            }

            Spacer().frame(width: 44)
        }
        .font(.caption2.weight(.semibold))
        .foregroundColor(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(Color(.systemGroupedBackground))
    }
    
    private func habitCardView(habitName: String) -> some View {
        let stats = cachedStats[habitName] ?? HabitStats(completed: 0, missed: 0, noData: 0, total: 0, percentage: 0, currentStreak: 0, maxStreak: 0, habitName: habitName)
        let pointsStats = cachedPoints[habitName] ?? (earned: 0.0, allocated: 0.0)
        let disciplineScore = cachedDiscipline[habitName] ?? calculateDisciplineScoreForHabit(habitName)
        let habitColor = Color.blue
        
        return HStack(spacing: 0) {
            Button(action: {
                selectedHabit = habitName
                showDetailedView = true
            }) {
                VStack(spacing: 8) {
                    // Header with habit name and frequency
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(habitColor)
                                    .frame(width: 6, height: 6)
                                
                                Text(habitName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(nil) // Allow unlimited lines
                            }
                            
                            if filterMode == "discipline" {
                                let repeatInterval = cachedRepeatInterval[habitName] ?? 1
                                let frequencyText = repeatInterval == 1 ? "Daily" : repeatInterval == 7 ? "Weekly" : "Every \(repeatInterval)d"
                                Text(frequencyText)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 10)
                            } else {
                                Text("\(stats.missed) missed")
                                    .font(.caption2)
                                    .foregroundColor(.red.opacity(0.8))
                                    .padding(.leading, 10)
                            }
                        }
                        
                        Spacer()
                        
                        // Main metric (compact)
                        VStack(spacing: 1) {
                            if filterMode == "discipline" {
                                let levelColors = disciplineScore.disciplineLevel.color
                                Text(String(format: "%.2f", disciplineScore.disciplineScore))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(hex: levelColors.primary))
                                
                                Text("DMS")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                let percentageColor = getPercentageColor(stats.percentage)
                                Text("\(Int(stats.percentage))%")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(percentageColor)
                                
                                Text("Success")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Compact metrics
                    if filterMode == "discipline" {
                        compactDisciplineMetrics(disciplineScore: disciplineScore)
                    } else {
                        let evtStats = cachedEventStats[habitName] ?? (eventDays: 0, nonEventMisses: 0)
                        compactTraditionalMetrics(stats: stats, pointsStats: pointsStats, eventStats: evtStats)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Download button with notes count badge
            Button(action: {
                downloadHabitNotes(habitName: habitName)
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.down.doc")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                    
                    let notesCount = getNotesCount(habitName: habitName)
                    if notesCount > 0 {
                        Text("\(notesCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(Color.red))
                            .offset(x: -2, y: 10)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color(.systemBackground))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.systemGray6), lineWidth: 0.5)
        )
    }
    
    private func compactDisciplineMetrics(disciplineScore: DisciplineMuscleScore) -> some View {
        let levelColors = disciplineScore.disciplineLevel.color
        
        return VStack(spacing: 4) {
            // Discipline level badge (show full name)
            HStack {
                Text(disciplineScore.disciplineLevel.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: levelColors.primary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: levelColors.background))
                    )
                
                Spacer()
            }
            
            // Ultra-compact metrics row
            HStack(spacing: 6) {
                // Completed/Expected
                VStack(spacing: 0) {
                    Text("\(disciplineScore.completedDays)/\(disciplineScore.totalDays)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Done")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Penalty
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", disciplineScore.decayPenalty))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(disciplineScore.decayPenalty > 0 ? .red : .green)
                    
                    Text("Penalty")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Current Streak
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        if disciplineScore.currentStreak > 0 {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Text("\(disciplineScore.currentStreak)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(disciplineScore.currentStreak > 0 ? .orange : .secondary)
                    }
                    
                    Text("Streak")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Streak Bonus
                VStack(spacing: 0) {
                    Text("+\(String(format: "%.2f", disciplineScore.streakBonus))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Bonus")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func compactTraditionalMetrics(stats: HabitStats, pointsStats: (earned: Double, allocated: Double), eventStats: (eventDays: Int, nonEventMisses: Int)) -> some View {
        
        return VStack(spacing: 4) {
            // First row: Completed/Total, Current Streak, Max Streak
            HStack(spacing: 6) {
                // Completed/Total
                VStack(spacing: 0) {
                    Text("\(stats.completed)/\(stats.total)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Score")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Current Streak
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        if stats.currentStreak > 0 {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        Text("\(stats.currentStreak)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(stats.currentStreak > 0 ? .orange : .secondary)
                    }
                    
                    Text("Current")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Max Streak
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        Image(systemName: "trophy.fill")
                            .font(.caption2)
                            .foregroundColor(.purple)
                        
                        Text("\(stats.maxStreak)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                    }
                    
                    Text("Best")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            
            // Second row: Points, Event Days, Non-Event Misses
            HStack(spacing: 6) {
                // Points
                VStack(spacing: 0) {
                    Text("\(Int(pointsStats.earned))/\(Int(pointsStats.allocated))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Points")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Event Days
                VStack(spacing: 0) {
                    Text("\(eventStats.eventDays)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    
                    Text("Events")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Non-Event Misses
                VStack(spacing: 0) {
                    Text("\(eventStats.nonEventMisses)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Misses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func getPercentageColor(_ percentage: Double) -> Color {
        if percentage >= 80 {
            return .green
        } else if percentage >= 60 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if filterMode == "discipline" {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Text("No Discipline Data")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Create repeating tasks to start building your discipline muscle")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
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
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var overallDisciplineView: some View {
        let allScores = filteredHabitNames.compactMap { cachedDiscipline[$0] }
        let overallDiscipline = DisciplineMuscleCalculator.calculateOverallDiscipline(scores: allScores)
        let levelColors = overallDiscipline.level.color
        
        // Get habit frequency info
        let habitFrequencies = getHabitFrequencies()
        
        return VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Overall Discipline")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    let filterText = selectedRepeatFilter != nil ? " (filtered)" : ""
                    Text("\(allScores.count) habits\(filterText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Discipline Level Badge (show full name)
                Text(overallDiscipline.level.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(Color(hex: levelColors.primary))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: levelColors.background))
                    )
                
                // DMS Score
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.2f", overallDiscipline.score))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(hex: levelColors.primary))
                    
                    Text("DMS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Ultra-compact stats row — single pass over allScores
            let totalDone = allScores.reduce(0) { $0 + $1.completedDays }
            let totalPenalty = allScores.reduce(0.0) { $0 + $1.decayPenalty }
            let maxStreak = allScores.reduce(0) { max($0, $1.currentStreak) }
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("\(totalDone)")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text("done")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 2) {
                    Text(String(format: "%.1f", totalPenalty))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("penalty")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 2) {
                    Text("\(maxStreak)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text("streak")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(6)
        .padding(.horizontal)
        .padding(.bottom, 2)
    }
    
    private func getHabitFrequencies() -> String {
        let filteredTasks = tasks.filter { task in
            guard task.repeatAgain != nil else { return false }
            guard filteredHabitNames.contains(task.title) else { return false }
            return true
        }
        
        let frequencies = Dictionary(grouping: filteredTasks) { $0.repeatAgain ?? 1 }
        
        let frequencyStrings = frequencies.map { interval, tasks in
            let count = Set(tasks.map { $0.title }).count
            switch interval {
            case 1: return "\(count) daily"
            case 7: return "\(count) weekly"
            default: return "\(count) every \(interval)d"
            }
        }.sorted()
        
        return frequencyStrings.joined(separator: ", ")
    }
    
    // MARK: - Computed Properties
    
    private var habitTasks: [Task] {
        tasks.filter { $0.repeatAgain != nil }
    }
    
    private var filteredHabitNames: [String] {
        // Build lookup dictionary once — avoids re-filtering tasks for every habit name
        var tasksByTitle: [String: [Task]] = [:]
        for task in tasks where task.repeatAgain != nil {
            tasksByTitle[task.title, default: []].append(task)
        }
        let allHabitNames = tasksByTitle.keys.sorted()

        return allHabitNames
            .filter { name in
                guard let selectedRepeat = selectedRepeatFilter else { return true }
                let repeatValues = Set(tasksByTitle[name]!.compactMap { $0.repeatAgain })
                return repeatValues.contains { $0 <= selectedRepeat }
            }
            .filter { name in
                guard !selectedTagsFilter.isEmpty else { return true }
                return tasksByTitle[name]!.contains { task in
                    if selectedTagsFilter.contains("") && task.taskDescription.trimmingCharacters(in: .whitespaces).isEmpty {
                        return true
                    }
                    let taskTags = task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    return !Set(taskTags).isDisjoint(with: selectedTagsFilter)
                }
            }
            .filter { name in
                guard !appliedMultiSearch.isEmpty else { return true }
                let terms = appliedMultiSearch
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                return terms.isEmpty || terms.contains { name.localizedCaseInsensitiveContains($0) }
            }
            .filter { name in
                guard percentageFilter != "all" else { return true }
                let pct = cachedStats[name]?.percentage ?? 0
                return percentageFilter == "above" ? pct >= 85 : pct < 85
            }
    }
    
    private var dateRange: [Date] { cachedDateRange }

    private var overviewBarChartEntries: [HabitOverviewBarEntry] {
        var entries = filteredHabitNames.map { name in
            let stats = cachedStats[name]
            let interval = cachedRepeatInterval[name] ?? 1
            return HabitOverviewBarEntry(
                label: "\(name)\n(\(interval)d)",
                completed: stats?.completed ?? 0,
                missed: stats?.missed ?? 0
            )
        }
        switch chartSortOrder {
        case "desc": entries.sort {
            let r0 = $0.total > 0 ? Double($0.completed) / Double($0.total) : 0
            let r1 = $1.total > 0 ? Double($1.completed) / Double($1.total) : 0
            return r0 < r1  // low ratio first → high ratio at top (High → Low)
        }
        case "asc": entries.sort {
            let r0 = $0.total > 0 ? Double($0.completed) / Double($0.total) : 0
            let r1 = $1.total > 0 ? Double($1.completed) / Double($1.total) : 0
            return r0 > r1  // high ratio first → low ratio at top (Low → High)
        }
        default: break
        }
        return entries
    }

    private var overviewBarChartSegments: [HabitOverviewBarSegment] {
        overviewBarChartEntries.flatMap { entry in
            [
                HabitOverviewBarSegment(label: entry.label, status: "Completed", count: entry.completed),
                HabitOverviewBarSegment(label: entry.label, status: "Missed", count: entry.missed)
            ]
        }
    }

    // MARK: - Stats Recomputation

    private func recomputeAllStats() {
        let cal = Calendar.current
        var dates: [Date] = []
        var cur = fromDate
        while cur <= toDate {
            dates.append(cur)
            cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur
        }
        cachedDateRange = dates

        let htasks = tasks.filter { $0.repeatAgain != nil }
        let names = Array(Set(htasks.map { $0.title }))

        var stats: [String: HabitStats] = [:]
        var pts: [String: (earned: Double, allocated: Double)] = [:]
        var disc: [String: DisciplineMuscleScore] = [:]
        var evts: [String: (eventDays: Int, nonEventMisses: Int)] = [:]
        var repeatIntervals: [String: Int] = [:]

        for name in names {
            stats[name] = calculateStatsForHabit(name)
            pts[name] = calculatePointsForHabit(name)
            disc[name] = calculateDisciplineScoreForHabit(name)
            evts[name] = calculateEventStatsForHabit(name)
            repeatIntervals[name] = htasks.first { $0.title == name }?.repeatAgain ?? 1
        }

        cachedStats = stats
        cachedPoints = pts
        cachedDiscipline = disc
        cachedEventStats = evts
        cachedRepeatInterval = repeatIntervals

        var allTags = Set<String>()
        var countPerTag: [String: Set<String>] = [:]
        for task in htasks {
            let tags = task.taskDescription.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for tag in tags where !tag.isEmpty {
                allTags.insert(tag)
                countPerTag[tag, default: Set()].insert(task.title)
            }
            if task.taskDescription.trimmingCharacters(in: .whitespaces).isEmpty {
                allTags.insert("")
                countPerTag["", default: Set()].insert(task.title)
            }
        }
        cachedHabitTags = Array(allTags).sorted { f, s in
            if f.isEmpty && !s.isEmpty { return false }
            if !f.isEmpty && s.isEmpty { return true }
            return f < s
        }
        cachedHabitCountPerTag = countPerTag.mapValues { $0.count }
    }

    // MARK: - Helper Methods
    
    private func calculateDisciplineScoreForHabit(_ habitName: String) -> DisciplineMuscleScore {
        let cal = Calendar.current
        let habitSpecificTasks = tasks.filter { $0.repeatAgain != nil && $0.title == habitName }
        let repeatInterval = habitSpecificTasks.first?.repeatAgain ?? 1

        // Index tasks by day once — avoids O(dates × tasks) nested filter
        let tasksByDay = Dictionary(grouping: habitSpecificTasks) { cal.startOfDay(for: $0.date ?? Date()) }

        var dailyCompletions: [(Date, Bool)] = []
        for date in dateRange {
            let day = cal.startOfDay(for: date)
            guard let dayTasks = tasksByDay[day], !dayTasks.isEmpty else { continue }
            dailyCompletions.append((date, dayTasks.contains(where: { $0.completed })))
        }

        return DisciplineMuscleCalculator.calculateScore(
            completions: dailyCompletions,
            totalDays: dailyCompletions.count,
            repeatInterval: repeatInterval
        )
    }

    private func calculateStatsForHabit(_ habitName: String) -> HabitStats {
        var completed = 0
        var missed = 0
        let cal = Calendar.current

        let habitSpecificTasks = tasks.filter { $0.repeatAgain != nil && $0.title == habitName }

        // Index tasks by day once — avoids O(dates × tasks) nested filter
        let tasksByDay = Dictionary(grouping: habitSpecificTasks) { cal.startOfDay(for: $0.date ?? Date()) }

        var dailyCompletions: [(Date, Bool)] = []
        for date in dateRange {
            let day = cal.startOfDay(for: date)
            guard let dayTasks = tasksByDay[day], !dayTasks.isEmpty else { continue }
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
            habitName: habitName
        )
    }
    
    private func calculatePointsForHabit(_ habitName: String) -> (earned: Double, allocated: Double) {
        let cal = Calendar.current
        let habitSpecificTasks = tasks.filter { $0.repeatAgain != nil && $0.title == habitName }

        // Index by day once — avoids O(dates × tasks) nested filter
        let tasksByDay = Dictionary(grouping: habitSpecificTasks) { cal.startOfDay(for: $0.date ?? Date()) }

        var earnedPoints = 0.0
        var allocatedPoints = 0.0
        for date in dateRange {
            let day = cal.startOfDay(for: date)
            for task in tasksByDay[day] ?? [] {
                allocatedPoints += task.weight
                if task.completed { earnedPoints += task.effectiveWeight }
            }
        }
        return (earned: earnedPoints, allocated: allocatedPoints)
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
    
    // MARK: - DMS Guide and Settings
    
    private var filtersAccordion: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showFilters.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.blue)
                    
                    Text("Advanced Filters")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if hasActiveFilters() {
                        Text("(\(getActiveFiltersText()))")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if showFilters {
                VStack(spacing: 16) {
                    // Date Range Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Date Range")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                        }
                        
                        VStack(spacing: 8) {
                            DateRangeShiftControl(start: $pendingFromDate, end: $pendingToDate, onShift: {
                                fromDate = pendingFromDate
                                toDate = pendingToDate
                                saveDateSettings()
                            })
                            DatePicker("Start Date", selection: $pendingFromDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                            DatePicker("End Date", selection: $pendingToDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                            Button {
                                fromDate = pendingFromDate
                                toDate = pendingToDate
                                saveDateSettings()
                            } label: {
                                Text("Apply Dates")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                    
                    // Dynamic Multi-Search Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Habits")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            if !appliedMultiSearch.isEmpty {
                                Button("Clear") {
                                    multiSearchText = ""
                                    appliedMultiSearch = ""
                                    showSearchSuggestions = false
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }

                        Text("Type to search — pick from the dropdown or type comma-separated terms")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("exercise, study, …", text: $multiSearchText)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: multiSearchText) { _, _ in
                                    showSearchSuggestions = true
                                }
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    showSearchSuggestions.toggle()
                                }
                            } label: {
                                Image(systemName: showSearchSuggestions ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 28, height: 28)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))
                            }
                            Button {
                                appliedMultiSearch = multiSearchText
                                showSearchSuggestions = false
                                showSaveSearchField = false
                            } label: {
                                Text("Apply")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                            }
                            if !appliedMultiSearch.isEmpty {
                                Button {
                                    multiSearchText = ""
                                    appliedMultiSearch = ""
                                    showSearchSuggestions = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Suggestions dropdown
                        if showSearchSuggestions && !searchSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text("Select habits")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            showSearchSuggestions = false
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                                Divider()

                                ScrollView {
                                    VStack(spacing: 0) {
                                        ForEach(searchSuggestions, id: \.self) { suggestion in
                                            let isSelected = selectedSearchTerms.contains(suggestion)
                                            Button(action: { toggleSuggestion(suggestion) }) {
                                                HStack(spacing: 8) {
                                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                        .font(.caption)
                                                        .foregroundColor(isSelected ? .blue : Color(.systemGray3))
                                                    Text(suggestion)
                                                        .font(.caption)
                                                        .foregroundColor(.primary)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 9)
                                                .background(isSelected ? Color.blue.opacity(0.06) : Color.clear)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            Divider()
                                                .padding(.leading, 10)
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.systemGray4), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                        }

                        // Selected terms as chips
                        let chips = selectedSearchTerms
                        if !chips.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(chips, id: \.self) { term in
                                        HStack(spacing: 3) {
                                            Text(term)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                                .padding(.leading, 8)
                                                .padding(.vertical, 4)
                                            Button(action: { toggleSuggestion(term) }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 9, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.8))
                                                    .padding(.trailing, 7)
                                                    .padding(.vertical, 4)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.indigo))
                                    }
                                }
                                .padding(.horizontal, 1)
                            }
                        }

                        if !appliedMultiSearch.isEmpty {
                            HStack(spacing: 8) {
                                if showSaveSearchField {
                                    TextField("Name this search…", text: $saveSearchName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                    Button {
                                        let trimmed = saveSearchName.trimmingCharacters(in: .whitespaces)
                                        if !trimmed.isEmpty {
                                            savedSearches.append(SavedSearch(name: trimmed, terms: appliedMultiSearch))
                                            persistSavedSearches()
                                            saveSearchName = ""
                                            showSaveSearchField = false
                                        }
                                    } label: {
                                        Text("Save")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Color.green, in: RoundedRectangle(cornerRadius: 7))
                                    }
                                    Button {
                                        showSaveSearchField = false
                                        saveSearchName = ""
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button {
                                        showSaveSearchField = true
                                    } label: {
                                        Label("Save this search", systemImage: "bookmark")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                            }
                        }

                        if !savedSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Saved Searches")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(savedSearches) { search in
                                            HStack(spacing: 0) {
                                                Button(action: {
                                                    multiSearchText = search.terms
                                                    appliedMultiSearch = search.terms
                                                    showSearchSuggestions = false
                                                }) {
                                                    Text(search.name)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(appliedMultiSearch == search.terms ? .white : .primary)
                                                        .padding(.leading, 10)
                                                        .padding(.vertical, 6)
                                                }
                                                .buttonStyle(PlainButtonStyle())

                                                Button(action: {
                                                    savedSearches.removeAll { $0.id == search.id }
                                                    persistSavedSearches()
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(appliedMultiSearch == search.terms ? .white.opacity(0.8) : .secondary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 6)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(appliedMultiSearch == search.terms ? Color.indigo : Color(.systemGray6))
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 1)
                                }
                            }
                        }
                    }
                    
                    // Repeat Frequency Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Repeat Frequency")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if selectedRepeatFilter != nil {
                                Button("Clear") {
                                    selectedRepeatFilter = nil
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(getAvailableRepeatValues(), id: \.self) { repeatValue in
                                    let isSelected = selectedRepeatFilter == repeatValue
                                    let habitCount = getHabitCountForRepeatValue(repeatValue)
                                    
                                    Button(action: {
                                        if selectedRepeatFilter == repeatValue {
                                            selectedRepeatFilter = nil
                                        } else {
                                            selectedRepeatFilter = repeatValue
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(getRepeatDisplayText(repeatValue))
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            
                                            Text("\(habitCount) habit\(habitCount == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? Color.blue : Color(.systemGray6))
                                        )
                                        .foregroundColor(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    
                    // Tags Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tags")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if !selectedTagsFilter.isEmpty {
                                Button("Clear") {
                                    selectedTagsFilter.removeAll()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(getAvailableHabitTags(), id: \.self) { tag in
                                    let isSelected = selectedTagsFilter.contains(tag)
                                    let habitCount = getHabitCountForTag(tag)
                                    
                                    Button(action: {
                                        if selectedTagsFilter.contains(tag) {
                                            selectedTagsFilter.remove(tag)
                                        } else {
                                            selectedTagsFilter.insert(tag)
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(tag.isEmpty ? "No Tag" : tag)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            
                                            Text("\(habitCount) habit\(habitCount == 1 ? "" : "s")")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(isSelected ? Color.green : Color(.systemGray6))
                                        )
                                        .foregroundColor(isSelected ? .white : .primary)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // Success Rate Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Success Rate")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Spacer()

                            if percentageFilter != "all" {
                                Button("Clear") { percentageFilter = "all" }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }

                        HStack(spacing: 8) {
                            ForEach([("all", "All", Color.blue), ("above", "≥ 85%", Color.green), ("below", "< 85%", Color.orange)], id: \.0) { value, label, color in
                                let isSelected = percentageFilter == value
                                Button(action: { percentageFilter = value }) {
                                    Text(label)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? color : Color(.systemGray6)))
                                        .foregroundColor(isSelected ? .white : .primary)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
    
    private var dmsGuideAccordion: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showDMSGuide.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    
                    Text("Discipline Muscle Score Guide")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: showDMSGuide ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if showDMSGuide {
                VStack(spacing: 12) {
                    // Formula Explanation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("📊 DMS Formula")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("DMS = (Completed - Penalty) ÷ Expected + Streak Bonus")
                            .font(.caption2)
                            .monospaced()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .cornerRadius(4)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚡ Streak Bonus = Longest Streak ÷ Expected")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            
                            Text("💥 Penalty Rules (consecutive misses):")
                                .font(.caption2)
                                .foregroundColor(.red)
                            
                            Text("  • 1 miss → 0 penalty")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("  • 2 misses → -0.5 penalty")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("  • 3+ misses → -0.5 + (extra × 1.0)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Score Levels Table
                    VStack(spacing: 0) {
                        // Header row
                        HStack {
                            Text("Score Range")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Text("Discipline Level")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        
                        // Score rows
                        ForEach(Array(DisciplineLevel.allCases.enumerated()), id: \.offset) { index, level in
                            HStack {
                                Text(level.scoreRangeText)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack {
                                    Text(level.rawValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    if level == .growing {
                                        Text("💪")
                                            .font(.caption)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(index % 2 == 0 ? Color(.systemBackground) : Color(.systemGray6).opacity(0.3))
                        }
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }
    
    private func loadHabitSettings() {
        habitSettings = HabitSettings.getOrCreate(context: modelContext)
        if let settings = habitSettings {
            fromDate = settings.fromDate
            pendingFromDate = settings.fromDate
            toDate = Date()
            pendingToDate = Date()
        }
        loadSavedSearches()
        recomputeAllStats()
    }

    private func saveDateSettings() {
        if let settings = habitSettings {
            settings.updateFromDate(fromDate, context: modelContext)
        } else {
            let newSettings = HabitSettings(fromDate: fromDate)
            modelContext.insert(newSettings)
            habitSettings = newSettings
            try? modelContext.save()
        }
    }
    
    // MARK: - Time Chart Data

    private var timeChartEntries: [TimeChartEntry] {
        var spentByTitle: [String: Double] = [:]
        var elapsedByTitle: [String: Double] = [:]

        for task in tasks {
            guard let taskDate = task.date,
                  taskDate >= fromDate && taskDate <= toDate else { continue }

            let allocated = task.allocatedTimeInMinutes
            let effectiveSpent: Double
            let effectiveElapsed: Double

            if let ts = task.timeSpent {
                // Recorded time spent: green = ts, red = remaining allocated
                effectiveSpent = ts
                effectiveElapsed = max(allocated, ts)
            } else if task.completed && allocated > 0 {
                // Completed, no time spent → full green
                effectiveSpent = allocated
                effectiveElapsed = allocated
            } else if !task.completed && allocated > 0 {
                // Not completed, no time spent → full red (missed)
                effectiveSpent = 0
                effectiveElapsed = allocated
            } else {
                continue
            }

            guard effectiveElapsed > 0 || effectiveSpent > 0 else { continue }

            spentByTitle[task.title, default: 0] += effectiveSpent
            elapsedByTitle[task.title, default: 0] += effectiveElapsed
        }

        let searchTerms = appliedMultiSearch
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var entries: [TimeChartEntry] = spentByTitle.keys.compactMap { title in
            let spent = spentByTitle[title] ?? 0
            let elapsed = elapsedByTitle[title] ?? 0
            guard spent > 0 || elapsed > 0 else { return nil }
            if !searchTerms.isEmpty && !searchTerms.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
                return nil
            }
            return TimeChartEntry(label: title, spent: spent, remaining: max(0, elapsed - spent))
        }

        switch timeChartSortOrder {
        case "desc": entries.sort {
            let r0 = $0.elapsed > 0 ? $0.spent / $0.elapsed : 0
            let r1 = $1.elapsed > 0 ? $1.spent / $1.elapsed : 0
            return r0 < r1  // low ratio first → high ratio at top (High → Low)
        }
        case "asc": entries.sort {
            let r0 = $0.elapsed > 0 ? $0.spent / $0.elapsed : 0
            let r1 = $1.elapsed > 0 ? $1.spent / $1.elapsed : 0
            return r0 > r1  // high ratio first → low ratio at top (Low → High)
        }
        default:     entries.sort { $0.label < $1.label }
        }

        return entries
    }

    private var timeChartSegments: [TimeChartSegment] {
        timeChartEntries.flatMap { entry in
            [
                TimeChartSegment(label: entry.label, status: "Spent",     minutes: entry.spent),
                TimeChartSegment(label: entry.label, status: "Remaining", minutes: entry.remaining)
            ]
        }
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        guard m > 0 else { return "0m" }
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
    }

    // MARK: - Search Suggestion Helpers

    private var selectedSearchTerms: [String] {
        multiSearchText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var currentPartialTerm: String {
        let text = multiSearchText
        if text.hasSuffix(",") || text.hasSuffix(", ") { return "" }
        return text.split(separator: ",").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? text.trimmingCharacters(in: .whitespaces)
    }

    private var searchSuggestions: [String] {
        let partial = currentPartialTerm
        let candidates: [String]
        if selectedView == "time" {
            let titlesInRange = Set(tasks.compactMap { task -> String? in
                guard let d = task.date, d >= fromDate && d <= toDate else { return nil }
                return task.title
            })
            candidates = titlesInRange.sorted()
        } else {
            candidates = cachedStats.keys.sorted()
        }
        return candidates.filter { name in
            partial.isEmpty || name.localizedCaseInsensitiveContains(partial)
        }
    }

    private func toggleSuggestion(_ name: String) {
        let partial = currentPartialTerm
        var terms = multiSearchText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let idx = terms.firstIndex(of: name) {
            terms.remove(at: idx)
        } else {
            // Replace the partial term (what was being typed) with the selected full name
            if !partial.isEmpty && partial != name {
                terms.removeAll { $0 == partial }
            }
            terms.append(name)
        }
        multiSearchText = terms.isEmpty ? "" : terms.joined(separator: ", ") + ", "
    }

    private func loadSavedSearches() {
        guard let data = UserDefaults.standard.data(forKey: "habitSavedSearches"),
              let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) else { return }
        savedSearches = decoded
    }

    private func persistSavedSearches() {
        guard let encoded = try? JSONEncoder().encode(savedSearches) else { return }
        UserDefaults.standard.set(encoded, forKey: "habitSavedSearches")
    }

    // MARK: - Filter Helper Methods
    
    private func getAvailableRepeatValues() -> [Int] {
        let repeatValues = Set(tasks.compactMap { $0.repeatAgain })
        return Array(repeatValues).sorted()
    }
    
    private func getHabitCountForRepeatValue(_ repeatValue: Int) -> Int {
        let habitNames = Set(tasks.filter { ($0.repeatAgain ?? 0) <= repeatValue && $0.repeatAgain != nil }.map { $0.title })
        return habitNames.count
    }
    
    private func getRepeatDisplayText(_ repeatValue: Int) -> String {
        switch repeatValue {
        case 1: return "≤ Daily"
        case 2: return "≤ Every 2d"
        case 3: return "≤ Every 3d"
        case 7: return "≤ Weekly"
        case 14: return "≤ Bi-weekly"
        case 30: return "≤ Monthly"
        default: return "≤ Every \(repeatValue)d"
        }
    }
    
    private func hasActiveFilters() -> Bool {
        return selectedRepeatFilter != nil || !appliedMultiSearch.isEmpty || !selectedTagsFilter.isEmpty || percentageFilter != "all"
    }
    
    private func getAvailableHabitTags() -> [String] { cachedHabitTags }

    private func getHabitCountForTag(_ tag: String) -> Int { cachedHabitCountPerTag[tag] ?? 0 }
    
    private func getActiveFiltersText() -> String {
        var filters: [String] = []
        
        if let repeatFilter = selectedRepeatFilter {
            filters.append(getRepeatDisplayText(repeatFilter))
        }
        
        if !appliedMultiSearch.isEmpty {
            filters.append("Search: \(appliedMultiSearch)")
        }

        if percentageFilter != "all" {
            filters.append(percentageFilter == "above" ? "≥85%" : "<85%")
        }

        return filters.joined(separator: ", ")
    }
    
    private func calculateEventStatsForHabit(_ habitName: String) -> (eventDays: Int, nonEventMisses: Int) {
        let cal = Calendar.current
        let habitSpecificTasks = tasks.filter { $0.repeatAgain != nil && $0.title == habitName }

        // Index habit tasks and event days by startOfDay — avoids O(n²) nested search
        let tasksByDay = Dictionary(grouping: habitSpecificTasks) { cal.startOfDay(for: $0.date ?? Date()) }
        let eventDaySet = Set(eventDays.compactMap { $0.hasAnyEvent ? cal.startOfDay(for: $0.date) : nil })

        var eventDaysCount = 0
        var nonEventMissesCount = 0
        for date in dateRange {
            let day = cal.startOfDay(for: date)
            guard let dayTasks = tasksByDay[day], !dayTasks.isEmpty else { continue }
            let isCompleted = dayTasks.contains(where: { $0.completed })
            let isMissed = dayTasks.contains(where: { $0.notCompleted })
            if eventDaySet.contains(day) {
                eventDaysCount += 1
            } else if isMissed && !isCompleted {
                nonEventMissesCount += 1
            }
        }
        return (eventDays: eventDaysCount, nonEventMisses: nonEventMissesCount)
    }
    
    // MARK: - PDF Generation
    
    private func getNotesCount(habitName: String) -> Int {
        let habitTasks = tasks.filter { task in
            guard task.title == habitName,
                  let taskDate = task.date,
                  taskDate >= fromDate && taskDate <= toDate,
                  let notes = task.notes,
                  !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return true
        }
        return habitTasks.count
    }
    
    private func downloadHabitNotes(habitName: String) {
        // Get tasks for this habit within date range
        let habitTasks = tasks.filter { task in
            guard task.title == habitName,
                  let taskDate = task.date,
                  taskDate >= fromDate && taskDate <= toDate else {
                return false
            }
            return true
        }
        
        // Check if there are any notes
        let tasksWithNotes = habitTasks.filter { task in
            guard let notes = task.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return true
        }
        
        if tasksWithNotes.isEmpty {
            // Show alert that there are no notes
            noNotesHabitName = habitName
            showNoNotesAlert = true
            return
        }
        
        // Generate PDF
        if let url = HabitNotesPDFGenerator.generatePDF(
            habitName: habitName,
            tasks: habitTasks,
            fromDate: fromDate,
            toDate: toDate
        ) {
            pdfURL = url
            showShareSheet = true
        }
    }
}

struct SavedSearch: Codable, Identifiable {
    let id: UUID
    var name: String
    var terms: String

    init(name: String, terms: String) {
        self.id = UUID()
        self.name = name
        self.terms = terms
    }
}

struct TimeChartEntry: Identifiable {
    let id = UUID()
    let label: String
    let spent: Double     // green (minutes)
    let remaining: Double // red = max(0, elapsed - spent) (minutes)
    var elapsed: Double { spent + remaining }
}

struct TimeChartSegment: Identifiable {
    let id = UUID()
    let label: String
    let status: String   // "Spent" or "Remaining"
    let minutes: Double
}

struct HabitOverviewBarEntry: Identifiable {
    let id = UUID()
    let label: String
    let completed: Int
    let missed: Int
    var total: Int { completed + missed }
}

struct HabitOverviewBarSegment: Identifiable {
    let id = UUID()
    let label: String
    let status: String
    let count: Int
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - ShareSheet for PDF Export
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HabitOverviewView()
        .modelContainer(for: [Task.self, Habit.self, HabitSettings.self], inMemory: true)
}