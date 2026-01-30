import SwiftData
import Foundation

// Extension to calculate task metrics
extension Task {
    /// Calculate completion rate and current streak for the last N days from a reference date
    func calculateMetrics(days: Int, allTasks: [Task], referenceDate: Date = Date()) -> TaskMetrics {
        guard self.repeatAgain != nil else {
            return TaskMetrics(completionRate: 0, currentStreak: 0, completed: 0, total: 0)
        }
        
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        
        // Get all tasks with the same title (same habit)
        let habitTasks = allTasks.filter { $0.title == self.title && $0.repeatAgain != nil }
        
        // Track daily completions
        var dailyCompletions: [(Date, Bool)] = []
        var completed = 0
        var total = 0
        
        // Check each day in the range
        var currentDate = startDate
        while currentDate <= endDate {
            let dayTasks = habitTasks.filter { task in
                guard let taskDate = task.date else { return false }
                return calendar.isDate(taskDate, inSameDayAs: currentDate)
            }
            
            // Only count days where tasks exist
            if !dayTasks.isEmpty {
                let isCompleted = dayTasks.contains(where: { $0.completed })
                dailyCompletions.append((currentDate, isCompleted))
                
                if isCompleted {
                    completed += 1
                }
                total += 1
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        
        // Calculate completion rate
        let completionRate = total > 0 ? Double(completed) / Double(total) * 100 : 0
        
        // Calculate current streak (going backwards from reference date)
        var currentStreak = 0
        let reversedCompletions = dailyCompletions.reversed()
        for (_, isCompleted) in reversedCompletions {
            if isCompleted {
                currentStreak += 1
            } else {
                break
            }
        }
        
        return TaskMetrics(completionRate: completionRate, currentStreak: currentStreak, completed: completed, total: total)
    }
}

struct TaskMetrics {
    let completionRate: Double // Percentage (0-100)
    let currentStreak: Int // Number of consecutive completed days
    let completed: Int // Number of completed days
    let total: Int // Total number of days with tasks
    
    var formattedCompletionRate: String {
        return String(format: "%.0f%%", completionRate)
    }
    
    var formattedScore: String {
        return "\(completed)/\(total)"
    }
    
    var completionColor: String {
        if completionRate >= 80 {
            return "green"
        } else if completionRate >= 60 {
            return "orange"
        } else {
            return "red"
        }
    }
}
