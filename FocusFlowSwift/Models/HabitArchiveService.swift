import SwiftData
import Foundation

class HabitArchiveService {
    
    static func archiveHabit(habitName: String, tasks: [Task], context: ModelContext) -> ArchivedHabit? {
        // Get all tasks for this habit
        let habitTasks = tasks.filter { $0.title == habitName && $0.repeatAgain != nil }
        
        guard !habitTasks.isEmpty else { return nil }
        
        // Get basic habit info
        let firstTask = habitTasks.first!
        let repeatFrequency = firstTask.repeatAgain ?? 1
        let habitDescription = firstTask.taskDescription
        
        // Calculate date range
        let sortedTasks = habitTasks.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        let startDate = sortedTasks.first?.date ?? Date()
        let endDate = Date()
        
        // Calculate completion statistics
        let completedTasks = habitTasks.filter { $0.completed }
        let totalCompletedDays = completedTasks.count
        let totalTasks = habitTasks.count
        
        // Calculate expected days based on frequency and date range
        let totalDays = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let totalExpectedDays = max(1, totalDays / repeatFrequency)
        let totalMissedDays = max(0, totalExpectedDays - totalCompletedDays)
        let completionPercentage = totalExpectedDays > 0 ? (Double(totalCompletedDays) / Double(totalExpectedDays)) * 100.0 : 0.0
        
        // Calculate streaks
        let streakData = calculateStreaks(habitTasks: habitTasks, repeatFrequency: repeatFrequency)
        
        // Calculate time and weight statistics
        let totalTimeSpent = habitTasks.compactMap { $0.timeSpent }.reduce(0, +)
        let averageWeight = habitTasks.isEmpty ? 0.0 : habitTasks.map { $0.weight }.reduce(0, +) / Double(habitTasks.count)
        
        // Get first and last completion dates
        let completedTasksSorted = completedTasks.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        let firstCompletionDate = completedTasksSorted.first?.date
        let lastCompletionDate = completedTasksSorted.last?.date
        
        // Calculate weekly and monthly completion rates
        let weeklyRates = calculateWeeklyCompletionRates(habitTasks: habitTasks, startDate: startDate, endDate: endDate, repeatFrequency: repeatFrequency)
        let monthlyRates = calculateMonthlyCompletionRates(habitTasks: habitTasks, startDate: startDate, endDate: endDate, repeatFrequency: repeatFrequency)
        
        // Calculate additional statistics
        let weeklyStats = calculateWeeklyStats(habitTasks: habitTasks, startDate: startDate, endDate: endDate)
        let averageDaysBetweenCompletions = calculateAverageDaysBetweenCompletions(completedTasks: completedTasks)
        
        // Create archived habit
        let archivedHabit = ArchivedHabit(
            habitName: habitName,
            habitDescription: habitDescription,
            startDate: startDate,
            endDate: endDate,
            repeatFrequency: repeatFrequency,
            totalExpectedDays: totalExpectedDays,
            totalCompletedDays: totalCompletedDays,
            totalMissedDays: totalMissedDays,
            completionPercentage: completionPercentage,
            longestStreak: streakData.longestStreak,
            currentStreakAtArchive: streakData.currentStreak,
            averageWeight: averageWeight,
            totalTimeSpent: totalTimeSpent,
            firstCompletionDate: firstCompletionDate,
            lastCompletionDate: lastCompletionDate,
            totalTasks: totalTasks,
            weeklyCompletionRates: weeklyRates,
            monthlyCompletionRates: monthlyRates,
            bestWeekCompletions: weeklyStats.best,
            worstWeekCompletions: weeklyStats.worst,
            averageDaysBetweenCompletions: averageDaysBetweenCompletions
        )
        
        return archivedHabit
    }
    
    private static func calculateStreaks(habitTasks: [Task], repeatFrequency: Int) -> (longestStreak: Int, currentStreak: Int) {
        let completedTasks = habitTasks.filter { $0.completed }.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        guard !completedTasks.isEmpty else { return (0, 0) }
        
        var longestStreak = 0
        var currentStreak = 0
        var streakCount = 1
        
        for i in 1..<completedTasks.count {
            let previousDate = completedTasks[i-1].date ?? Date.distantPast
            let currentDate = completedTasks[i].date ?? Date.distantPast
            
            let daysDifference = Calendar.current.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            
            // Check if the gap matches the expected frequency (allowing some tolerance)
            if daysDifference <= repeatFrequency + 1 {
                streakCount += 1
            } else {
                longestStreak = max(longestStreak, streakCount)
                streakCount = 1
            }
        }
        
        longestStreak = max(longestStreak, streakCount)
        
        // Calculate current streak (from the end)
        if let lastCompletedDate = completedTasks.last?.date {
            let daysSinceLastCompletion = Calendar.current.dateComponents([.day], from: lastCompletedDate, to: Date()).day ?? 0
            
            if daysSinceLastCompletion <= repeatFrequency + 1 {
                // Still within the expected frequency, calculate current streak
                currentStreak = 1
                for i in stride(from: completedTasks.count - 2, through: 0, by: -1) {
                    let currentDate = completedTasks[i+1].date ?? Date.distantPast
                    let previousDate = completedTasks[i].date ?? Date.distantPast
                    
                    let daysDifference = Calendar.current.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
                    
                    if daysDifference <= repeatFrequency + 1 {
                        currentStreak += 1
                    } else {
                        break
                    }
                }
            }
        }
        
        return (longestStreak, currentStreak)
    }
    
    private static func calculateWeeklyCompletionRates(habitTasks: [Task], startDate: Date, endDate: Date, repeatFrequency: Int) -> [Double] {
        var weeklyRates: [Double] = []
        let calendar = Calendar.current
        
        var currentWeekStart = startDate
        while currentWeekStart < endDate {
            let weekEnd = min(calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart, endDate)
            
            let weekTasks = habitTasks.filter { task in
                guard let taskDate = task.date else { return false }
                return taskDate >= currentWeekStart && taskDate <= weekEnd
            }
            
            let completedInWeek = weekTasks.filter { $0.completed }.count
            let expectedInWeek = max(1, 7 / repeatFrequency) // Expected completions in a week
            let weekRate = expectedInWeek > 0 ? (Double(completedInWeek) / Double(expectedInWeek)) * 100.0 : 0.0
            
            weeklyRates.append(min(100.0, weekRate)) // Cap at 100%
            
            currentWeekStart = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        }
        
        return weeklyRates
    }
    
    private static func calculateMonthlyCompletionRates(habitTasks: [Task], startDate: Date, endDate: Date, repeatFrequency: Int) -> [Double] {
        var monthlyRates: [Double] = []
        let calendar = Calendar.current
        
        var currentMonthStart = startDate
        while currentMonthStart < endDate {
            let monthEnd = min(calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? currentMonthStart, endDate)
            
            let monthTasks = habitTasks.filter { task in
                guard let taskDate = task.date else { return false }
                return taskDate >= currentMonthStart && taskDate < monthEnd
            }
            
            let completedInMonth = monthTasks.filter { $0.completed }.count
            let daysInMonth = calendar.dateComponents([.day], from: currentMonthStart, to: monthEnd).day ?? 30
            let expectedInMonth = max(1, daysInMonth / repeatFrequency)
            let monthRate = expectedInMonth > 0 ? (Double(completedInMonth) / Double(expectedInMonth)) * 100.0 : 0.0
            
            monthlyRates.append(min(100.0, monthRate)) // Cap at 100%
            
            currentMonthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? currentMonthStart
        }
        
        return monthlyRates
    }
    
    private static func calculateWeeklyStats(habitTasks: [Task], startDate: Date, endDate: Date) -> (best: Int, worst: Int) {
        let calendar = Calendar.current
        var weeklyCompletions: [Int] = []
        
        var currentWeekStart = startDate
        while currentWeekStart < endDate {
            let weekEnd = min(calendar.date(byAdding: .day, value: 6, to: currentWeekStart) ?? currentWeekStart, endDate)
            
            let weekTasks = habitTasks.filter { task in
                guard let taskDate = task.date else { return false }
                return taskDate >= currentWeekStart && taskDate <= weekEnd
            }
            
            let completedInWeek = weekTasks.filter { $0.completed }.count
            weeklyCompletions.append(completedInWeek)
            
            currentWeekStart = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        }
        
        let best = weeklyCompletions.max() ?? 0
        let worst = weeklyCompletions.min() ?? 0
        
        return (best, worst)
    }
    
    private static func calculateAverageDaysBetweenCompletions(completedTasks: [Task]) -> Double {
        let sortedTasks = completedTasks.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }
        
        guard sortedTasks.count > 1 else { return 0.0 }
        
        var totalDays = 0
        for i in 1..<sortedTasks.count {
            let previousDate = sortedTasks[i-1].date ?? Date.distantPast
            let currentDate = sortedTasks[i].date ?? Date.distantPast
            let days = Calendar.current.dateComponents([.day], from: previousDate, to: currentDate).day ?? 0
            totalDays += days
        }
        
        return Double(totalDays) / Double(sortedTasks.count - 1)
    }
}