import SwiftUI
import SwiftData
import Foundation

struct HabitDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var tasks: [Task]
    @State private var selectedHabit = ""
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var filterMode = "all"
    @State private var showDeleteConfirmation = false
    @State private var habitToDelete = ""
    @State private var searchText = ""
    
    var initialHabit: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            headerView
            
            // Overall streak summary
            if !filteredHabitNames.isEmpty {
                overallStreakSummary
            }
            
            dateFilters
                HStack {
        Image(systemName: "magnifyingglass")
        TextField("Search habits…", text: $searchText)
          .textFieldStyle(.roundedBorder)
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
    habitCalendar
    statsView
} else {
    emptyStateView
}
    }
    .navigationTitle("Habit Tracker")
    .onAppear {
      // Use initialHabit if provided, otherwise use first available
      if let initialHabit = initialHabit, filteredHabitNames.contains(initialHabit) {
        selectedHabit = initialHabit
      } else if selectedHabit.isEmpty, let first = filteredHabitNames.first {
        selectedHabit = first
      }
    }
    .onChange(of: filteredHabitNames) { _, newList in
      // Reset selectedHabit if it was filtered out
      if !newList.contains(selectedHabit) {
        selectedHabit = newList.first ?? ""
      }
    }

        .alert("Delete Habit", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteHabit(habitToDelete)
            }
        } message: {
            Text("Are you sure you want to delete this habit and all its tasks?")
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Habit Tracker")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
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
        HStack {
            DatePicker("From", selection: $fromDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            
            DatePicker("To", selection: $toDate, displayedComponents: .date)
                .datePickerStyle(.compact)
        }
        .padding(.horizontal)
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
      .filter { searchText.isEmpty
               || $0.localizedCaseInsensitiveContains(searchText) }
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
        let stats = calculateStatsForHabit(habitName)
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
    
    private func habitDayView(date: Date) -> some View {
        let status = getStatusForDay(date: date)
        
        return VStack(spacing: 2) {
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
        .foregroundColor(status == .noData ? .primary : .white)
        .cornerRadius(6)
    }
    
    private var statsView: some View {
        let stats = calculateStatsForHabit(selectedHabit)
        let percentage = stats.total > 0 ? Int((Double(stats.completed) / Double(stats.total)) * 100) : 0
        
        return VStack(spacing: 16) {
            // First row: Completed and Missed
            HStack(spacing: 20) {
                statItem(title: "Completed", value: stats.completed, color: .green)
                statItem(title: "Missed", value: stats.missed, color: .red)
            }
            
            // Second row: Streaks
            HStack(spacing: 20) {
                statItem(title: "Current Streak", value: stats.currentStreak, color: .blue)
                statItem(title: "Max Streak", value: stats.maxStreak, color: .purple)
            }
            
            // Completion rate
            Text("\(percentage)% Completion Rate")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(percentage >= 80 ? .green : percentage >= 60 ? .orange : .red)
        }
        .padding()
    }
    
    private func statItem(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                if title.contains("Streak") {
                    Image(systemName: title.contains("Current") ? "flame.fill" : "trophy.fill")
                        .foregroundColor(color)
                        .font(.caption)
                } else {
                    Rectangle()
                        .fill(color)
                        .frame(width: 15, height: 15)
                        .cornerRadius(2)
                }
                
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var overallStreakSummary: some View {
        let allStats = filteredHabitNames.map { calculateStatsForHabit($0) }
        let totalCurrentStreak = allStats.reduce(0) { $0 + $1.currentStreak }
        let maxStreakOverall = allStats.map { $0.maxStreak }.max() ?? 0
        let activeStreaks = allStats.filter { $0.currentStreak > 0 }.count
        
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
    
    // MARK: - Helper Methods
    
    private func getStatusForDay(date: Date) -> HabitStatus {
        let dayTasks = filteredHabitTasks.filter { task in
            task.title == selectedHabit &&
            Calendar.current.isDate(task.date ?? Date(), inSameDayAs: date)
        }
        
        if dayTasks.isEmpty { return .noData }
        if dayTasks.contains(where: { $0.completed }) { return .completed }
        if dayTasks.contains(where: { $0.notCompleted }) { return .missed }
        return .noData
    }
    
    private func colorForStatus(_ status: HabitStatus) -> Color {
        switch status {
        case .completed: return .green
        case .missed: return .red
        case .noData: return .gray.opacity(0.3)
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
            maxStreak: streaks.max
        )
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
    case completed, missed, noData
}

struct HabitStats {
    let completed: Int
    let missed: Int
    let noData: Int
    let total: Int
    let percentage: Double
    let currentStreak: Int
    let maxStreak: Int
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
}

#Preview {
    HabitDashboardView()
        .modelContainer(for: [Task.self], inMemory: true)
}
