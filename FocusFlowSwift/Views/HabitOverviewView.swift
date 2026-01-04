import SwiftUI
import SwiftData
import Foundation

struct HabitOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var filterMode = "all"
    @State private var searchText = ""
    @State private var selectedHabit: String? = nil
    @State private var showDetailedView = false
    @State private var showDMSGuide = false
    @State private var showFilters = false
    @State private var selectedRepeatFilter: Int? = nil
    @State private var habitSettings: HabitSettings?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with filters
                headerView
                
                // Overall Discipline Level Display (only when discipline filter is selected)
                if filterMode == "discipline" && !filteredHabitNames.isEmpty {
                    overallDisciplineView
                }
                
                if filteredHabitNames.isEmpty {
                    emptyStateView
                } else {
                    // Main table view
                    habitTableView
                }
            }
            .navigationTitle("Habit Overview")
            .onAppear {
                loadHabitSettings()
            }
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
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            // Filter controls
            HStack {
                Picker("Filter", selection: $filterMode) {
                    Text("All").tag("all")
                    Text("Discipline").tag("discipline")
                    Text("Repeats").tag("repeats")
                }
                .pickerStyle(.segmented)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Filters Accordion
            filtersAccordion
            
            // DMS Guide Accordion (only show when discipline filter is selected)
            if filterMode == "discipline" {
                dmsGuideAccordion
            }
        }
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }
    
    private var habitTableView: some View {
        VStack(spacing: 0) {
            // Scrollable content with cards instead of table
            ScrollView {
                LazyVStack(spacing: 6) {
                    // Habit cards
                    ForEach(filteredHabitNames, id: \.self) { habitName in
                        habitCardView(habitName: habitName)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
            }
        }
    }
    
    private func habitCardView(habitName: String) -> some View {
        let stats = calculateStatsForHabit(habitName)
        let pointsStats = calculatePointsForHabit(habitName)
        let disciplineScore = calculateDisciplineScoreForHabit(habitName)
        let habitColor = Color.blue // All habits use blue color
        
        return Button(action: {
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
                            let repeatInterval = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }.first?.repeatAgain ?? 1
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
                    compactTraditionalMetrics(stats: stats, pointsStats: pointsStats)
                }
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.systemGray6), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private func compactTraditionalMetrics(stats: HabitStats, pointsStats: (earned: Double, allocated: Double)) -> some View {
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
        let allScores = filteredHabitNames.map { calculateDisciplineScoreForHabit($0) }
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
            
            // Ultra-compact stats row
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("\(allScores.map(\.completedDays).reduce(0, +))")
                        .font(.caption2)
                        .fontWeight(.bold)
                    Text("done")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 2) {
                    Text(String(format: "%.1f", allScores.map(\.decayPenalty).reduce(0, +)))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    Text("penalty")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 2) {
                    Text("\(allScores.map(\.currentStreak).max() ?? 0)")
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
        let allHabitNames = Array(Set(habitTasks.map { $0.title })).sorted()
        
        return allHabitNames
            .filter { name in
                // Apply repeat frequency filter if selected
                if let selectedRepeat = selectedRepeatFilter {
                    let habitTasks = tasks.filter { $0.title == name && $0.repeatAgain != nil }
                    let habitRepeatValues = Set(habitTasks.compactMap { $0.repeatAgain })
                    
                    // Show habits with repeat values <= selectedRepeat
                    return habitRepeatValues.contains { $0 <= selectedRepeat }
                }
                return true
            }
            .filter { searchText.isEmpty || $0.localizedCaseInsensitiveContains(searchText) }
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
    
    // MARK: - Helper Methods
    
    private func calculateDisciplineScoreForHabit(_ habitName: String) -> DisciplineMuscleScore {
        // Get tasks for this specific habit
        let habitSpecificTasks = tasks.filter { task in
            guard task.repeatAgain != nil && task.title == habitName else { return false }
            return true // Show all repeating tasks for discipline calculation
        }
        
        // Get the repeat interval from the first task (assuming all tasks with same name have same interval)
        let repeatInterval = habitSpecificTasks.first?.repeatAgain ?? 1
        
        // Create array to track daily completion status
        var dailyCompletions: [(Date, Bool)] = []
        
        // Calculate completions for each date in range
        for date in dateRange {
            let dayTasks = habitSpecificTasks.filter { task in
                Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
            }
            
            if !dayTasks.isEmpty {
                let isCompleted = dayTasks.contains(where: { $0.completed })
                dailyCompletions.append((date, isCompleted))
            }
        }
        
        // Use DisciplineMuscleCalculator to get the score with repeat interval
        return DisciplineMuscleCalculator.calculateScore(
            completions: dailyCompletions,
            totalDays: dateRange.count,
            repeatInterval: repeatInterval
        )
    }
    
    private func calculateStatsForHabit(_ habitName: String) -> HabitStats {
        var completed = 0
        var missed = 0
        
        // Get tasks for this specific habit
        let habitSpecificTasks = tasks.filter { task in
            guard task.repeatAgain != nil && task.title == habitName else { return false }
            return true // Show all repeating tasks
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
            maxStreak: streaks.max
        )
    }
    
    private func calculatePointsForHabit(_ habitName: String) -> (earned: Double, allocated: Double) {
        let habitSpecificTasks = tasks.filter { task in
            guard task.repeatAgain != nil && task.title == habitName else { return false }
            return true // Show all repeating tasks
        }
        
        var earnedPoints: Double = 0
        var allocatedPoints: Double = 0
        
        // Calculate points for each date in range
        for date in dateRange {
            let dayTasks = habitSpecificTasks.filter { task in
                Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
            }
            
            for task in dayTasks {
                allocatedPoints += task.weight
                if task.completed {
                    earnedPoints += task.effectiveWeight
                }
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
                        
                        HStack {
                            DatePicker("From", selection: $fromDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .onChange(of: fromDate) { _, newValue in
                                    saveDateSettings()
                                }
                            
                            DatePicker("To", selection: $toDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .onChange(of: toDate) { _, newValue in
                                    saveDateSettings()
                                }
                        }
                    }
                    
                    // Search Filter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Habits")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if !searchText.isEmpty {
                                Button("Clear") {
                                    searchText = ""
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                            TextField("Search habits…", text: $searchText)
                                .textFieldStyle(.roundedBorder)
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
            toDate = settings.toDate
        }
    }
    
    private func saveDateSettings() {
        if let settings = habitSettings {
            settings.updateDates(from: fromDate, to: toDate, context: modelContext)
        } else {
            let newSettings = HabitSettings(fromDate: fromDate, toDate: toDate)
            modelContext.insert(newSettings)
            habitSettings = newSettings
            try? modelContext.save()
        }
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
        return selectedRepeatFilter != nil || !searchText.isEmpty
    }
    
    private func getActiveFiltersText() -> String {
        var filters: [String] = []
        
        if let repeatFilter = selectedRepeatFilter {
            filters.append(getRepeatDisplayText(repeatFilter))
        }
        
        if !searchText.isEmpty {
            filters.append("Search: \(searchText)")
        }
        
        return filters.joined(separator: ", ")
    }
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

#Preview {
    HabitOverviewView()
        .modelContainer(for: [Task.self, Habit.self, HabitSettings.self], inMemory: true)
}