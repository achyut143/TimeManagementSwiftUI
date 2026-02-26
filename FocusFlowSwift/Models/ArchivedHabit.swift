import SwiftData
import Foundation

@Model
class ArchivedHabit {
    var id: UUID = UUID()
    var habitName: String
    var habitDescription: String
    var startDate: Date
    var endDate: Date
    var repeatFrequency: Int // Days between repetitions
    var totalExpectedDays: Int // Total days the habit should have been done
    var totalCompletedDays: Int // Total days the habit was actually completed
    var totalMissedDays: Int // Total days the habit was missed
    var completionPercentage: Double // Percentage of expected days completed
    var longestStreak: Int // Longest consecutive streak
    var currentStreakAtArchive: Int // Streak when archived
    var averageWeight: Double // Average weight of habit tasks
    var totalTimeSpent: Double // Total time spent on habit (in minutes)
    var firstCompletionDate: Date? // Date of first completion
    var lastCompletionDate: Date? // Date of last completion
    var archivedDate: Date
    
    // Additional statistics
    var totalTasks: Int // Total number of habit tasks created
    
    // Store as JSON Data to avoid transformer issues with corrupted data
    var weeklyCompletionRatesData: Data? // Weekly completion rates as JSON
    var monthlyCompletionRatesData: Data? // Monthly completion rates as JSON
    
    // Computed properties for easy access
    var weeklyCompletionRates: [Double] {
        get {
            guard let data = weeklyCompletionRatesData else { return [] }
            return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
        }
        set {
            weeklyCompletionRatesData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var monthlyCompletionRates: [Double] {
        get {
            guard let data = monthlyCompletionRatesData else { return [] }
            return (try? JSONDecoder().decode([Double].self, from: data)) ?? []
        }
        set {
            monthlyCompletionRatesData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var bestWeekCompletions: Int // Most completions in a single week
    var worstWeekCompletions: Int // Least completions in a single week
    var averageDaysBetweenCompletions: Double // Average gap between completions
    
    init(
        habitName: String,
        habitDescription: String = "",
        startDate: Date,
        endDate: Date,
        repeatFrequency: Int,
        totalExpectedDays: Int,
        totalCompletedDays: Int,
        totalMissedDays: Int,
        completionPercentage: Double,
        longestStreak: Int,
        currentStreakAtArchive: Int,
        averageWeight: Double,
        totalTimeSpent: Double,
        firstCompletionDate: Date?,
        lastCompletionDate: Date?,
        totalTasks: Int,
        weeklyCompletionRates: [Double] = [],
        monthlyCompletionRates: [Double] = [],
        bestWeekCompletions: Int = 0,
        worstWeekCompletions: Int = 0,
        averageDaysBetweenCompletions: Double = 0.0
    ) {
        self.id = UUID()
        self.habitName = habitName
        self.habitDescription = habitDescription
        self.startDate = startDate
        self.endDate = endDate
        self.repeatFrequency = repeatFrequency
        self.totalExpectedDays = totalExpectedDays
        self.totalCompletedDays = totalCompletedDays
        self.totalMissedDays = totalMissedDays
        self.completionPercentage = completionPercentage
        self.longestStreak = longestStreak
        self.currentStreakAtArchive = currentStreakAtArchive
        self.averageWeight = averageWeight
        self.totalTimeSpent = totalTimeSpent
        self.firstCompletionDate = firstCompletionDate
        self.lastCompletionDate = lastCompletionDate
        self.archivedDate = Date()
        self.totalTasks = totalTasks
        self.weeklyCompletionRatesData = try? JSONEncoder().encode(weeklyCompletionRates)
        self.monthlyCompletionRatesData = try? JSONEncoder().encode(monthlyCompletionRates)
        self.bestWeekCompletions = bestWeekCompletions
        self.worstWeekCompletions = worstWeekCompletions
        self.averageDaysBetweenCompletions = averageDaysBetweenCompletions
    }
    
    // Computed properties for display
    var formattedDuration: String {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        if days < 7 {
            return "\(days) day\(days == 1 ? "" : "s")"
        } else if days < 30 {
            let weeks = days / 7
            return "\(weeks) week\(weeks == 1 ? "" : "s")"
        } else {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s")"
        }
    }
    
    var formattedCompletionPercentage: String {
        return String(format: "%.1f%%", completionPercentage)
    }
    
    var formattedTotalTimeSpent: String {
        let hours = Int(totalTimeSpent / 60)
        let minutes = Int(totalTimeSpent.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    var habitFrequencyDescription: String {
        switch repeatFrequency {
        case 1: return "Daily"
        case 2: return "Every 2 days"
        case 3: return "Every 3 days"
        case 7: return "Weekly"
        case 14: return "Bi-weekly"
        case 30: return "Monthly"
        default: return "Every \(repeatFrequency) days"
        }
    }
    
    var performanceLevel: String {
        switch completionPercentage {
        case 90...100: return "Excellent"
        case 75..<90: return "Good"
        case 60..<75: return "Fair"
        case 40..<60: return "Poor"
        default: return "Very Poor"
        }
    }
    
    var performanceLevelColor: String {
        switch completionPercentage {
        case 90...100: return "green"
        case 75..<90: return "blue"
        case 60..<75: return "orange"
        case 40..<60: return "red"
        default: return "gray"
        }
    }
}