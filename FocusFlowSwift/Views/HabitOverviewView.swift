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
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with filters
                headerView
                
                if filteredHabitNames.isEmpty {
                    emptyStateView
                } else {
                    // Main table view
                    habitTableView
                }
            }
            .navigationTitle("Habit Overview")
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
        VStack(spacing: 16) {
            // Filter controls
            HStack {
                Picker("Filter", selection: $filterMode) {
                    Text("All").tag("all")
                    Text("Routines").tag("routines")
                    Text("Repeats").tag("repeats")
                }
                .pickerStyle(.segmented)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Date filters
            HStack {
                DatePicker("From", selection: $fromDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                
                DatePicker("To", selection: $toDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
            }
            .padding(.horizontal)
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search habits…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(.systemGroupedBackground))
    }
    
    private var habitTableView: some View {
        VStack(spacing: 0) {
            // Fixed table header
            tableHeaderView
                .background(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                .zIndex(1)
            
            // Scrollable content
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Habit rows
                    ForEach(filteredHabitNames, id: \.self) { habitName in
                        habitRowView(habitName: habitName)
                    }
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    private var tableHeaderView: some View {
        HStack(spacing: 8) {
            Text("Habit")
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            Text("Score")
                .frame(width: 65)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            Text("Current")
                .frame(width: 55)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            Text("Best")
                .frame(width: 45)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
            
            Text("Points")
                .frame(width: 65)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [Color(.systemGray6), Color(.systemGray5)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private func habitRowView(habitName: String) -> some View {
        let stats = calculateStatsForHabit(habitName)
        let pointsStats = calculatePointsForHabit(habitName)
        let habitColor = habitName.lowercased().contains("routine") ? Color.purple : Color.blue
        let percentageColor = getPercentageColor(stats.percentage)
        let percentageBackgroundColor = percentageColor.opacity(0.15)
        
        return Button(action: {
            selectedHabit = habitName
            showDetailedView = true
        }) {
            HStack(spacing: 8) {
                // Habit name with indicator - now with full name on new line
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(habitColor)
                            .frame(width: 10, height: 10)
                        
                        Text(habitName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    
                    Text("\(stats.missed) missed")
                        .font(.system(size: 10))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.leading, 18) // Align with habit name
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Score (completed/total)
                VStack(spacing: 2) {
                    Text("\(stats.completed)/\(stats.total)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("\(Int(stats.percentage))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(percentageColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(percentageBackgroundColor)
                        )
                }
                .frame(width: 65)
                
                // Current streak
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        if stats.currentStreak > 0 {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                        Text("\(stats.currentStreak)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(stats.currentStreak > 0 ? .orange : .secondary)
                    }
                    
                    if stats.currentStreak > 0 {
                        Text("days")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 55)
                
                // Max streak
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.purple)
                        
                        Text("\(stats.maxStreak)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.purple)
                    }
                }
                .frame(width: 45)
                
                // Points (earned/allocated)
                VStack(spacing: 2) {
                    Text("\(Int(pointsStats.earned))/\(Int(pointsStats.allocated))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if pointsStats.allocated > 0 {
                        let pointsPercentage = Int((pointsStats.earned / pointsStats.allocated) * 100)
                        Text("\(pointsPercentage)%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.blue.opacity(0.15))
                            )
                    }
                }
                .frame(width: 65)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemBackground))
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            Rectangle()
                .fill(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .fill(Color(.systemGray6))
                        .frame(height: 0.5),
                    alignment: .bottom
                )
        )
        .overlay(
            // Hover effect
            Rectangle()
                .fill(Color.blue.opacity(0.05))
                .opacity(0)
        )
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var habitTasks: [Task] {
        tasks.filter { $0.repeatAgain != nil }
    }
    
    private var filteredHabitNames: [String] {
        let allHabitNames = Array(Set(habitTasks.map { $0.title })).sorted()
        
        return allHabitNames
            .filter { name in
                switch filterMode {
                case "routines": return name.lowercased().contains("routine")
                case "repeats": return !name.lowercased().contains("routine")
                default: return true
                }
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
            maxStreak: streaks.max
        )
    }
    
    private func calculatePointsForHabit(_ habitName: String) -> (earned: Double, allocated: Double) {
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
}

#Preview {
    HabitOverviewView()
        .modelContainer(for: [Task.self, Habit.self], inMemory: true)
}