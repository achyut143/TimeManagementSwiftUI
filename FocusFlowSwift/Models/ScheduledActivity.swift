import SwiftData
import Foundation

@Model
class ScheduledActivity {
    var name: String
    var scheduledTimes: [Date] // Times of day (using Date for time components)
    var windowDuration: TimeInterval // Duration in seconds (e.g., 10 minutes = 600 seconds)
    var isActive: Bool
    var createdAt: Date
    
    init(name: String, scheduledTimes: [Date] = [], windowDuration: TimeInterval = 600, isActive: Bool = true) {
        self.name = name
        self.scheduledTimes = scheduledTimes
        self.windowDuration = windowDuration
        self.isActive = isActive
        self.createdAt = Date()
    }
    
    // Get next scheduled time for today
    func nextScheduledTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Convert scheduled times to today's dates
        let todayTimes = scheduledTimes.compactMap { scheduledTime -> Date? in
            let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today)
        }.sorted()
        
        // Find next time that hasn't passed yet
        for time in todayTimes {
            if time > now {
                return time
            }
        }
        
        // If no more times today, return first time tomorrow
        if let firstTime = todayTimes.first {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            let components = calendar.dateComponents([.hour, .minute], from: firstTime)
            return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: tomorrow)
        }
        
        return nil
    }
    
    // Check if currently in an active window
    func isInActiveWindow() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        for scheduledTime in scheduledTimes {
            let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let todayTime = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today) {
                let windowEnd = todayTime.addingTimeInterval(windowDuration)
                if now >= todayTime && now <= windowEnd {
                    return true
                }
            }
        }
        
        return false
    }
    
    // Get current window end time if in active window
    func currentWindowEndTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        for scheduledTime in scheduledTimes {
            let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let todayTime = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today) {
                let windowEnd = todayTime.addingTimeInterval(windowDuration)
                if now >= todayTime && now <= windowEnd {
                    return windowEnd
                }
            }
        }
        
        return nil
    }
}

@Model
class ActivityUsageHistory {
    var activityName: String
    var usedAt: Date
    var windowStartTime: Date
    var windowEndTime: Date
    var notes: String?
    
    init(activityName: String, usedAt: Date = Date(), windowStartTime: Date, windowEndTime: Date, notes: String? = nil) {
        self.activityName = activityName
        self.usedAt = usedAt
        self.windowStartTime = windowStartTime
        self.windowEndTime = windowEndTime
        self.notes = notes
    }
}