import SwiftData
import Foundation

enum RecurrenceType: String, Codable, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case quarterly = "Quarterly"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .daily:
            return "calendar"
        case .weekly:
            return "calendar.badge.clock"
        case .monthly:
            return "calendar.circle"
        case .quarterly:
            return "calendar.badge.plus"
        }
    }
    
    var resetDescription: String {
        switch self {
        case .daily:
            return "Credits reset daily at midnight"
        case .weekly:
            return "Credits reset monthly on the 1st"
        case .monthly:
            return "Credits reset quarterly (Jan, Apr, Jul, Oct)"
        case .quarterly:
            return "Credits reset yearly on January 1st"
        }
    }
}

@Model
class ScheduledActivity {
    var name: String
    var scheduledTimes: [Date] // Times of day (using Date for time components)
    var windowDuration: TimeInterval // Duration in seconds (e.g., 10 minutes = 600 seconds)
    var isActive: Bool
    var createdAt: Date
    
    // Recurrence pattern - optional to handle existing activities, defaults to daily
    var recurrenceType: RecurrenceType?
    var selectedWeekdays: [Int] = [] // For weekly: 1=Sunday, 2=Monday, etc.
    var selectedMonthDays: [Int] = [] // For monthly: 1-31
    var selectedMonths: [Int] = [] // For quarterly: 1-12
    
    // Reward system for unused windows
    var accumulatedWindowCredits: Int = 0 // Number of unused windows that can be used later
    var lastResetDate: Date? // Track when rewards were last reset to 0
    var windowsUsedInPeriod: Int = 0 // Track how many windows were used in current period
    var windowsSkippedInPeriod: Int = 0 // Track how many windows were skipped in current period
    
    // Attached reward system
    var attachedRewardId: UUID? // ID of the attached reward
    var rewardBurnAmount: Double = 0.0 // Amount to burn from reward when using activity (in reward's native units)
    var rewardBurnType: RewardBurnType? // Type of burn (time in minutes, money in dollars, or points) - optional for migration
    
    // Attached task system
    var attachedTaskId: UUID? // UUID of the attached task
    var taskTimeAmount: Double = 0.0 // Amount of time to add to task when using activity (in minutes)
    
    // Computed property to provide safe access to rewardBurnType with default
    var effectiveRewardBurnType: RewardBurnType {
        return rewardBurnType ?? .time
    }
    
    // Helper methods to check if attachments are configured
    var hasRewardAttachment: Bool {
        return attachedRewardId != nil && rewardBurnAmount > 0
    }
    
    var hasTaskAttachment: Bool {
        return attachedTaskId != nil && taskTimeAmount > 0
    }
    
    init(name: String, scheduledTimes: [Date] = [], windowDuration: TimeInterval = 600, isActive: Bool = true, recurrenceType: RecurrenceType = .daily, selectedWeekdays: [Int] = [], selectedMonthDays: [Int] = [], selectedMonths: [Int] = [], attachedRewardId: UUID? = nil, rewardBurnAmount: Double = 0.0, rewardBurnType: RewardBurnType? = .time, attachedTaskId: UUID? = nil, taskTimeAmount: Double = 0.0) {
        print("🏗️ Creating ScheduledActivity: \(name)")
        print("🏗️ Recurrence type: \(recurrenceType.displayName)")
        print("🏗️ Selected weekdays: \(selectedWeekdays)")
        print("🏗️ Selected month days: \(selectedMonthDays)")
        print("🏗️ Selected months: \(selectedMonths)")
        
        self.name = name
        self.scheduledTimes = scheduledTimes
        self.windowDuration = windowDuration
        self.isActive = isActive
        self.createdAt = Date()
        self.recurrenceType = recurrenceType
        self.selectedWeekdays = selectedWeekdays
        self.selectedMonthDays = selectedMonthDays
        self.selectedMonths = selectedMonths
        self.accumulatedWindowCredits = 0
        self.lastResetDate = nil
        self.windowsUsedInPeriod = 0
        self.windowsSkippedInPeriod = 0
        self.attachedRewardId = attachedRewardId
        self.rewardBurnAmount = rewardBurnAmount
        self.rewardBurnType = rewardBurnType
        self.attachedTaskId = attachedTaskId
        self.taskTimeAmount = taskTimeAmount
    }
    
    // Migration helper for existing activities
    func ensureMigration() {
        // This method ensures that existing activities are properly migrated
        // It's called whenever an activity is accessed to ensure compatibility
        
      
        
        // For existing activities that don't have recurrenceType set, default to daily
        if recurrenceType == nil {
            recurrenceType = .daily
            print("🔄 Migrated activity '\(name)' to daily recurrence (was nil)")
        }
        
        // For existing activities that might not have recurrence configuration,
        // we assume they should be daily activities
        if selectedWeekdays.isEmpty && selectedMonthDays.isEmpty && selectedMonths.isEmpty {
            // If recurrenceType is not daily, but no specific days are selected,
            // this suggests it's an old activity that should default to daily
            if recurrenceType != .daily {
                print("🔄 Migrating activity '\(name)' to daily recurrence (was \(recurrenceType?.rawValue ?? "unknown")) because no days selected")
                recurrenceType = .daily
            } else {
                print("✅ Activity '\(name)' confirmed as daily recurrence")
            }
        } else {
            print("✅ Activity '\(name)' has selections, keeping recurrence type: \(recurrenceType?.rawValue ?? "nil")")
        }
        
        // Ensure lastResetDate is set if it's nil
        if lastResetDate == nil {
            lastResetDate = Date()
            print("🔄 Set initial reset date for activity '\(name)'")
        }
        
        // Migrate reward burn type if needed (for existing activities)
        // This is a bit tricky since we can't check if it's nil directly with SwiftData
        // We'll handle this in the UI when loading activities
        
        print("🔍 MIGRATION COMPLETE: Final recurrenceType: \(recurrenceType?.rawValue ?? "nil")")
    }
    
    // Check if this activity needs migration (for UI to handle)
    func needsMigration() -> Bool {
        // An activity needs migration if it has no recurrence type set
        return recurrenceType == nil
    }
    
    // Get the effective recurrence type (with migration fallback)
    var effectiveRecurrenceType: RecurrenceType {
        ensureMigration()
        return recurrenceType ?? .daily
    }
    
    // Migration helper for existing activities (legacy method)
    func migrateToNewRecurrenceSystem() {
        ensureMigration()
    }
    
    // Get next scheduled time based on recurrence pattern
    func nextScheduledTime() -> Date? {
        ensureMigration() // Ensure migration before processing
        
        switch effectiveRecurrenceType {
        case .daily:
            return nextDailyScheduledTime()
        case .weekly:
            return nextWeeklyScheduledTime()
        case .monthly:
            return nextMonthlyScheduledTime()
        case .quarterly:
            return nextQuarterlyScheduledTime()
        }
    }
    
    private func nextDailyScheduledTime() -> Date? {
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
    
    private func nextWeeklyScheduledTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        
        // Check today first if it's a selected weekday
        let todayWeekday = calendar.component(.weekday, from: now)
        if selectedWeekdays.contains(todayWeekday) {
            let today = calendar.startOfDay(for: now)
            let todayTimes = scheduledTimes.compactMap { scheduledTime -> Date? in
                let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
                return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today)
            }.sorted()
            
            for time in todayTimes {
                if time > now {
                    return time
                }
            }
        }
        
        // Find next selected weekday
        for dayOffset in 1...7 {
            if let futureDate = calendar.date(byAdding: .day, value: dayOffset, to: now) {
                let futureWeekday = calendar.component(.weekday, from: futureDate)
                if selectedWeekdays.contains(futureWeekday) {
                    if let firstTime = scheduledTimes.first {
                        let dayStart = calendar.startOfDay(for: futureDate)
                        let components = calendar.dateComponents([.hour, .minute], from: firstTime)
                        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: dayStart)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func nextMonthlyScheduledTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        
        // Check today first if it's a selected month day
        let todayDay = calendar.component(.day, from: now)
        if selectedMonthDays.contains(todayDay) {
            let today = calendar.startOfDay(for: now)
            let todayTimes = scheduledTimes.compactMap { scheduledTime -> Date? in
                let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
                return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today)
            }.sorted()
            
            for time in todayTimes {
                if time > now {
                    return time
                }
            }
        }
        
        // Find next selected month day
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        
        // Check remaining days in current month
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 31
        for day in (todayDay + 1)...daysInMonth {
            if selectedMonthDays.contains(day) {
                if let targetDate = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: day)),
                   let firstTime = scheduledTimes.first {
                    let components = calendar.dateComponents([.hour, .minute], from: firstTime)
                    return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: targetDate)
                }
            }
        }
        
        // Check next month
        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) {
            let nextMonthComponents = calendar.dateComponents([.year, .month], from: nextMonth)
            for day in selectedMonthDays.sorted() {
                if let targetDate = calendar.date(from: DateComponents(year: nextMonthComponents.year, month: nextMonthComponents.month, day: day)),
                   let firstTime = scheduledTimes.first {
                    let components = calendar.dateComponents([.hour, .minute], from: firstTime)
                    return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: targetDate)
                }
            }
        }
        
        return nil
    }
    
    private func nextQuarterlyScheduledTime() -> Date? {
        let now = Date()
        let calendar = Calendar.current
        
        // Check today first if it's in a selected month and day
        let todayMonth = calendar.component(.month, from: now)
        let todayDay = calendar.component(.day, from: now)
        
        if selectedMonths.contains(todayMonth) && selectedMonthDays.contains(todayDay) {
            let today = calendar.startOfDay(for: now)
            let todayTimes = scheduledTimes.compactMap { scheduledTime -> Date? in
                let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
                return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today)
            }.sorted()
            
            for time in todayTimes {
                if time > now {
                    return time
                }
            }
        }
        
        // Find next quarterly occurrence
        let currentYear = calendar.component(.year, from: now)
        
        // Check remaining months in current year
        for month in selectedMonths.sorted() {
            if month >= todayMonth {
                for day in selectedMonthDays.sorted() {
                    if let targetDate = calendar.date(from: DateComponents(year: currentYear, month: month, day: day)),
                       targetDate > now,
                       let firstTime = scheduledTimes.first {
                        let components = calendar.dateComponents([.hour, .minute], from: firstTime)
                        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: targetDate)
                    }
                }
            }
        }
        
        // Check next year
        for month in selectedMonths.sorted() {
            for day in selectedMonthDays.sorted() {
                if let targetDate = calendar.date(from: DateComponents(year: currentYear + 1, month: month, day: day)),
                   let firstTime = scheduledTimes.first {
                    let components = calendar.dateComponents([.hour, .minute], from: firstTime)
                    return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: targetDate)
                }
            }
        }
        
        return nil
    }
    
    // Check if currently in an active window based on recurrence pattern
    func isInActiveWindow() -> Bool {
        ensureMigration() // Ensure migration before processing
        
        let now = Date()
        let calendar = Calendar.current
        
        // Check if today is a valid day for this activity
        if !isValidDayForActivity(date: now) {
            return false
        }
        
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
    
    // Check if a given date is valid for this activity based on recurrence pattern
    func isValidDayForActivity(date: Date) -> Bool {
        let calendar = Calendar.current
        
        switch effectiveRecurrenceType {
        case .daily:
            return true
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            return selectedWeekdays.contains(weekday)
        case .monthly:
            let day = calendar.component(.day, from: date)
            return selectedMonthDays.contains(day)
        case .quarterly:
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            return selectedMonths.contains(month) && selectedMonthDays.contains(day)
        }
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
    
    // MARK: - Reward System Methods
    
    // Check if we need to reset counters based on recurrence pattern
    func checkAndResetCounters() {
        ensureMigration() // Ensure migration before processing
        
        let calendar = Calendar.current
        let now = Date()
        
        // If lastResetDate is nil, set it and return (first time)
        guard let lastReset = lastResetDate else {
            lastResetDate = now
            return
        }
        
        let shouldReset: Bool
        switch effectiveRecurrenceType {
        case .daily:
            // Daily activities reset daily
            shouldReset = !calendar.isDate(lastReset, inSameDayAs: now)
        case .weekly:
            // Weekly activities reset monthly
            let lastMonth = calendar.dateInterval(of: .month, for: lastReset)
            let currentMonth = calendar.dateInterval(of: .month, for: now)
            shouldReset = lastMonth?.start != currentMonth?.start
        case .monthly:
            // Monthly activities reset quarterly
            let lastQuarter = getQuarterStart(for: lastReset, calendar: calendar)
            let currentQuarter = getQuarterStart(for: now, calendar: calendar)
            shouldReset = lastQuarter != currentQuarter
        case .quarterly:
            // Quarterly activities reset yearly
            let lastYear = calendar.component(.year, from: lastReset)
            let currentYear = calendar.component(.year, from: now)
            shouldReset = lastYear != currentYear
        }
        
        if shouldReset {
            resetCounters()
        }
    }
    
    private func getQuarterStart(for date: Date, calendar: Calendar) -> Date? {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))
    }
    
    // Reset counters based on recurrence type
    private func resetCounters() {
        // Only reset credits for daily activities
        if effectiveRecurrenceType == .daily {
            accumulatedWindowCredits = 0
        }
        // For weekly/monthly/quarterly, credits persist across periods
        
        windowsUsedInPeriod = 0
        windowsSkippedInPeriod = 0
        lastResetDate = Date()
    }
    
    // Mark a window as used (called when user uses the activity during window time)
    func markWindowAsUsed() {
        checkAndResetCounters()
        windowsUsedInPeriod += 1
    }
    
    // Mark a window as skipped and add window credit (called when window expires unused)
    func markWindowAsSkipped() {
        checkAndResetCounters()
        windowsSkippedInPeriod += 1
        
        // Add 1 window credit for the unused window
        accumulatedWindowCredits += 1
        
        print("🎁 Window skipped for '\(name)'. Added 1 window credit. Total: \(accumulatedWindowCredits) windows")
    }
    
    // Use accumulated window credits (called when user wants to spend window credits)
    func useWindowCredits(_ credits: Int, context: ModelContext) -> Bool {
        checkAndResetCounters()
        
        if accumulatedWindowCredits >= credits {
            accumulatedWindowCredits -= credits
            
            // Burn attached reward if configured
            print("🔍 DEBUG: useWindowCredits - About to check reward burning")
            if burnAttachedReward(context: context) {
                print("🔥 DEBUG: Successfully burned attached reward when using window credits")
            } else {
                print("ℹ️ DEBUG: No reward to burn or burning failed when using window credits")
            }
            
            // Add time to attached task if configured
            print("🔍 DEBUG: useWindowCredits - About to check task time addition")
            if addTimeToAttachedTask(context: context) {
                print("⏱️ DEBUG: Successfully added time to attached task when using window credits")
            } else {
                print("ℹ️ DEBUG: No task to add time to or addition failed when using window credits")
            }
            
            // Record credit usage in history
            let now = Date()
            let usage = ActivityUsageHistory(
                activityName: name,
                usedAt: now,
                windowStartTime: now, // For credit usage, start and end are the same
                windowEndTime: now,
                notes: "Used \(credits) window \(credits == 1 ? "credit" : "credits")",
                usageType: .creditUsage,
                creditsUsed: credits
            )
            context.insert(usage)
            
            print("⏰ Used \(credits) window credits for '\(name)'. Remaining: \(accumulatedWindowCredits) windows")
            return true
        } else {
            print("❌ Not enough window credits. Available: \(accumulatedWindowCredits), Requested: \(credits)")
            return false
        }
    }
    
    // Get formatted window credits string
    func formattedWindowCredits() -> String {
        if accumulatedWindowCredits == 1 {
            return "1 window"
        } else {
            return "\(accumulatedWindowCredits) windows"
        }
    }
    
    // Check if a specific window time has passed without being used (based on recurrence pattern)
    func hasWindowPassedUnused(windowTime: Date, on date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        
        // Check if the given date is valid for this activity
        if !isValidDayForActivity(date: date) {
            return false
        }
        
        let dayStart = calendar.startOfDay(for: date)
        
        // Convert window time to the specific date
        let components = calendar.dateComponents([.hour, .minute], from: windowTime)
        guard let windowDateTime = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: dayStart) else {
            return false
        }
        
        let windowEndTime = windowDateTime.addingTimeInterval(windowDuration)
        
        // Window has passed if current time is after window end time
        return now > windowEndTime
    }
    
    // Get all windows that have passed unused in the current period
    func getPassedUnusedWindows() -> [(Date, Date)] { // Returns (windowTime, date) pairs
        let calendar = Calendar.current
        let now = Date()
        var passedWindows: [(Date, Date)] = []
        
        // Check based on recurrence type
        switch effectiveRecurrenceType {
        case .daily:
            let today = calendar.startOfDay(for: now)
            for windowTime in scheduledTimes {
                if hasWindowPassedUnused(windowTime: windowTime, on: today) {
                    passedWindows.append((windowTime, today))
                }
            }
            
        case .weekly:
            // Check all valid days in current week
            if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) {
                var date = weekInterval.start
                while date < min(now, weekInterval.end) {
                    if isValidDayForActivity(date: date) {
                        for windowTime in scheduledTimes {
                            if hasWindowPassedUnused(windowTime: windowTime, on: date) {
                                passedWindows.append((windowTime, date))
                            }
                        }
                    }
                    date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                }
            }
            
        case .monthly:
            // Check all valid days in current month
            if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                var date = monthInterval.start
                while date < min(now, monthInterval.end) {
                    if isValidDayForActivity(date: date) {
                        for windowTime in scheduledTimes {
                            if hasWindowPassedUnused(windowTime: windowTime, on: date) {
                                passedWindows.append((windowTime, date))
                            }
                        }
                    }
                    date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                }
            }
            
        case .quarterly:
            // Check all valid days in current quarter
            let quarterStart = getQuarterStart(for: now, calendar: calendar) ?? now
            let quarterEnd = calendar.date(byAdding: .month, value: 3, to: quarterStart) ?? now
            
            var date = quarterStart
            while date < min(now, quarterEnd) {
                if isValidDayForActivity(date: date) {
                    for windowTime in scheduledTimes {
                        if hasWindowPassedUnused(windowTime: windowTime, on: date) {
                            passedWindows.append((windowTime, date))
                        }
                    }
                }
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            }
        }
        
        return passedWindows
    }
    
    // MARK: - Reward Integration Methods
    
    // Get the attached reward from context
    func getAttachedReward(context: ModelContext) -> Reward? {
        guard let rewardId = attachedRewardId else { return nil }
        
        let descriptor = FetchDescriptor<Reward>(
            predicate: #Predicate<Reward> { $0.id == rewardId }
        )
        
        do {
            let rewards = try context.fetch(descriptor)
            return rewards.first
        } catch {
            print("❌ Failed to fetch attached reward: \(error)")
            return nil
        }
    }
    
    // Burn reward when using activity
    func burnAttachedReward(context: ModelContext) -> Bool {
        print("🔍 DEBUG: Checking reward attachment - hasRewardAttachment: \(hasRewardAttachment)")
        print("🔍 DEBUG: attachedRewardId: \(attachedRewardId?.uuidString ?? "nil")")
        print("🔍 DEBUG: rewardBurnAmount: \(rewardBurnAmount)")
        
        guard hasRewardAttachment, let reward = getAttachedReward(context: context) else {
            print("❌ DEBUG: No reward attachment configured")
            print("❌ DEBUG: Reason - attachedRewardId is nil: \(attachedRewardId == nil)")
            print("❌ DEBUG: Reason - rewardBurnAmount is zero: \(rewardBurnAmount <= 0)")
            return false
        }
        
        // Convert burn amount to points based on burn type and reward type
        let pointsToBurn: Double
        
        switch effectiveRewardBurnType {
        case .time:
            // Burning time (minutes)
            if reward.type == .timeReward, let rate = reward.conversionRate, rate > 0 {
                // Convert minutes to points
                pointsToBurn = rewardBurnAmount / rate
            } else {
                // For non-time rewards, treat as points
                pointsToBurn = rewardBurnAmount
            }
        case .money:
            // Burning money (dollars)
            if reward.type == .moneyReward, let rate = reward.conversionRate, rate > 0 {
                // Convert dollars to points
                pointsToBurn = rewardBurnAmount / rate
            } else {
                // For non-money rewards, treat as points
                pointsToBurn = rewardBurnAmount
            }
        case .points:
            // Direct points burn
            pointsToBurn = rewardBurnAmount
        }
        
        // Burn the calculated points
        let comment = "Used activity: \(name) (\(effectiveRewardBurnType.displayName): \(formattedBurnAmount()))"
        reward.burnAmount(pointsToBurn, context: context, comment: comment)
        
        print("🔥 Burned \(formattedBurnAmount()) from reward '\(reward.name)' for activity '\(name)'")
        return true
    }
    
    // Format burn amount for display
    func formattedBurnAmount() -> String {
        switch effectiveRewardBurnType {
        case .time:
            let hours = Int(rewardBurnAmount) / 60
            let minutes = Int(rewardBurnAmount) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(Int(rewardBurnAmount)) min"
            }
        case .money:
            return "$\(String(format: "%.2f", rewardBurnAmount))"
        case .points:
            return "\(String(format: "%.1f", rewardBurnAmount)) pts"
        }
    }
    
    // Check if reward has enough balance for burn
    func canBurnReward(context: ModelContext) -> Bool {
        guard hasRewardAttachment, let reward = getAttachedReward(context: context) else {
            return false
        }
        
        // Calculate points needed
        let pointsNeeded: Double
        
        switch effectiveRewardBurnType {
        case .time:
            if reward.type == .timeReward, let rate = reward.conversionRate, rate > 0 {
                pointsNeeded = rewardBurnAmount / rate
            } else {
                pointsNeeded = rewardBurnAmount
            }
        case .money:
            if reward.type == .moneyReward, let rate = reward.conversionRate, rate > 0 {
                pointsNeeded = rewardBurnAmount / rate
            } else {
                pointsNeeded = rewardBurnAmount
            }
        case .points:
            pointsNeeded = rewardBurnAmount
        }
        
        // Check if reward has enough balance (including overdraft if allowed)
        if reward.currentAmount >= pointsNeeded {
            return true
        } else if reward.allowOverdraft {
            return true // Overdraft allowed
        } else {
            return false
        }
    }
    
    // MARK: - Task Integration Methods
    
    // Get the attached task from context (with smart repeat task handling)
    func getAttachedTask(context: ModelContext) -> Task? {
        guard let taskId = attachedTaskId else { return nil }
        
        // First try to find the exact task by UUID
        let exactDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { $0.id == taskId }
        )
        
        do {
            let exactTasks = try context.fetch(exactDescriptor)
            if let exactTask = exactTasks.first {
                print("🔍 Found exact task: '\(exactTask.title)' - completed: \(exactTask.completed), notCompleted: \(exactTask.notCompleted)")
                
                // Check if this task is still incomplete and relevant
                if !exactTask.completed && !exactTask.notCompleted {
                    // Task is still incomplete, use it
                    print("✅ Using original incomplete task")
                    return exactTask
                } else if exactTask.repeatAgain != nil {
                    // Task is completed/notCompleted but it's a repeating task
                    // Look for today's task first, then other incomplete instances
                    print("🔄 Original task is completed/notCompleted, looking for better instance")
                    return findBestRepeatTask(originalTask: exactTask, context: context)
                } else {
                    // Non-repeating task that's completed/notCompleted
                    print("⚠️ Non-repeating task is completed/notCompleted, still using it")
                    return exactTask
                }
            }
        } catch {
            print("❌ Failed to fetch exact attached task: \(error)")
        }
        
        // If exact task not found, try title-based search for today's task
        print("⚠️ Exact task not found, searching by title for today's task")
        return findTaskByTitleToday(taskId: taskId, context: context)
    }
    
    // Find the best repeat task instance (prioritizing today's task)
    private func findBestRepeatTask(originalTask: Task, context: ModelContext) -> Task? {
        let taskTitle = originalTask.title
        let taskStartTime = originalTask.startTime
        let taskEndTime = originalTask.endTime
        let taskRepeatAgain = originalTask.repeatAgain
        
        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { task in
                task.title == taskTitle &&
                task.startTime == taskStartTime &&
                task.endTime == taskEndTime &&
                task.repeatAgain == taskRepeatAgain
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        
        do {
            let repeatTasks = try context.fetch(descriptor)
            let today = Date()
            let calendar = Calendar.current
            
            print("🔍 Found \(repeatTasks.count) repeat task instances for '\(taskTitle)'")
            
            // PRIORITY 1: Find today's incomplete task
            for task in repeatTasks {
                guard let taskDate = task.date else { continue }
                
                if calendar.isDate(taskDate, inSameDayAs: today) && !task.completed && !task.notCompleted {
                    print("🎯 Found TODAY'S incomplete task: '\(task.title)' dated \(taskDate)")
                    return task
                }
            }
            
            // PRIORITY 2: Find any incomplete task (today or future)
            for task in repeatTasks {
                guard let taskDate = task.date else { continue }
                
                if !task.completed && !task.notCompleted {
                    if calendar.isDate(taskDate, inSameDayAs: today) || taskDate > today {
                        print("✅ Found future incomplete task: '\(task.title)' dated \(taskDate)")
                        return task
                    }
                }
            }
            
            // PRIORITY 3: Find most recent incomplete task (past)
            for task in repeatTasks.reversed() {
                guard let taskDate = task.date else { continue }
                
                if !task.completed && !task.notCompleted {
                    print("✅ Found past incomplete task: '\(task.title)' dated \(taskDate)")
                    return task
                }
            }
            
            // PRIORITY 4: Return most recent task (even if completed)
            if let latestTask = repeatTasks.last {
                print("⚠️ Using latest task (may be completed): '\(latestTask.title)' dated \(latestTask.date?.description ?? "no date")")
                return latestTask
            }
            
        } catch {
            print("❌ Failed to fetch repeat tasks: \(error)")
        }
        
        return nil
    }
    
    // Fallback: Find task by title matching for today
    private func findTaskByTitleToday(taskId: UUID, context: ModelContext) -> Task? {
        // First, try to get the original task to extract its title
        let exactDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { $0.id == taskId }
        )
        
        var originalTitle: String?
        do {
            let exactTasks = try context.fetch(exactDescriptor)
            originalTitle = exactTasks.first?.title
        } catch {
            print("❌ Failed to fetch original task for title: \(error)")
        }
        
        guard let title = originalTitle else {
            print("❌ Could not determine original task title")
            return nil
        }
        
        // Search for today's task with matching title
        let today = Date()
        let calendar = Calendar.current
        
        let todayDescriptor = FetchDescriptor<Task>()
        
        do {
            let allTasks = try context.fetch(todayDescriptor)
            
            // Find today's task with matching title
            for task in allTasks {
                guard let taskDate = task.date else { continue }
                
                if calendar.isDate(taskDate, inSameDayAs: today) && 
                   task.title == title && 
                   !task.completed && 
                   !task.notCompleted {
                    print("🎯 Found TODAY'S task by title match: '\(task.title)'")
                    return task
                }
            }
            
            // If no today's incomplete task, find any today's task with matching title
            for task in allTasks {
                guard let taskDate = task.date else { continue }
                
                if calendar.isDate(taskDate, inSameDayAs: today) && task.title == title {
                    print("⚠️ Found TODAY'S task by title (may be completed): '\(task.title)'")
                    return task
                }
            }
            
        } catch {
            print("❌ Failed to search tasks by title: \(error)")
        }
        
        return nil
    }
    
    // Check if the attached task needs updating (for UI display)
    func needsTaskAttachmentUpdate(context: ModelContext) -> (needsUpdate: Bool, suggestedTask: Task?) {
        guard let taskId = attachedTaskId else { return (false, nil) }
        
        // Try to find the exact task
        let exactDescriptor = FetchDescriptor<Task>(
            predicate: #Predicate<Task> { $0.id == taskId }
        )
        
        do {
            let exactTasks = try context.fetch(exactDescriptor)
            if let exactTask = exactTasks.first {
                // Check if this task is completed/notCompleted and has repeats
                if (exactTask.completed || exactTask.notCompleted) && exactTask.repeatAgain != nil {
                    // Look for newer incomplete instance
                    if let newerTask = findBestRepeatTask(originalTask: exactTask, context: context) {
                        // Only suggest update if we found a different task
                        if newerTask.id != exactTask.id {
                            return (true, newerTask)
                        }
                    }
                }
                return (false, nil) // Current task is fine
            } else {
                // Original task not found, might need updating
                return (true, nil)
            }
        } catch {
            return (false, nil)
        }
    }
    
    // Fallback method to find task by legacy ID (for migration purposes)
    private func findTaskByLegacyId(taskId: UUID, context: ModelContext) -> Task? {
        print("⚠️ Could not find task with ID: \(taskId.uuidString)")
        print("🔍 Attempting title-based search for today's task...")
        return findTaskByTitleToday(taskId: taskId, context: context)
    }
    
    // Add time to attached task when using activity
    func addTimeToAttachedTask(context: ModelContext) -> Bool {
        print("🔍 DEBUG: Checking task attachment - hasTaskAttachment: \(hasTaskAttachment)")
        print("🔍 DEBUG: attachedTaskId: \(attachedTaskId?.uuidString ?? "nil")")
        print("🔍 DEBUG: taskTimeAmount: \(taskTimeAmount)")
        
        guard hasTaskAttachment else {
            print("❌ DEBUG: No task attachment configured")
            print("❌ DEBUG: Reason - attachedTaskId is nil: \(attachedTaskId == nil)")
            print("❌ DEBUG: Reason - taskTimeAmount is zero: \(taskTimeAmount <= 0)")
            return false
        }
        
        guard let task = getAttachedTask(context: context) else {
            print("❌ DEBUG: Failed to get attached task")
            return false
        }
        
        print("✅ DEBUG: Found attached task: '\(task.title)' (ID: \(task.id.uuidString))")
        
        // If we found a different task instance (e.g., newer repeat task), update the attachment
        if task.id != attachedTaskId {
            print("🔄 DEBUG: Updating attachment to newer task instance")
            attachedTaskId = task.id
            // Note: We don't save the context here as it will be saved by the caller
        }
        
        // Add time to task's timeSpent property
        let currentTimeSpent = task.timeSpent ?? 0.0
        task.timeSpent = currentTimeSpent + taskTimeAmount
        
        print("⏱️ Added \(formattedTaskTime()) to task '\(task.title)' for activity '\(name)'")
        print("⏱️ Task time spent: \(currentTimeSpent) min → \(task.timeSpent ?? 0.0) min")
        
        // Save the context to persist changes
        do {
            try context.save()
            print("✅ DEBUG: Successfully saved task time update")
        } catch {
            print("❌ DEBUG: Failed to save task time update: \(error)")
        }
        
        // Check if task completion should earn reward points
        checkTaskRewardEarning(task: task, context: context)
        
        return true
    }
    
    // Format task time amount for display
    func formattedTaskTime() -> String {
        let hours = Int(taskTimeAmount) / 60
        let minutes = Int(taskTimeAmount) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(Int(taskTimeAmount)) min"
        }
    }
    
    // Check if task time addition should earn reward points
    private func checkTaskRewardEarning(task: Task, context: ModelContext) {
        // Only award points if the task is actually completed
        guard task.completed else {
            return
        }
        
        // Check if task has reward links
        if let rewardLinks = task.rewardLinks, !rewardLinks.isEmpty {
            // Task has reward links - add to linked rewards
            for rewardLink in rewardLinks {
                if let reward = rewardLink.reward {
                    let pointsToEarn = task.effectiveWeight
                    reward.addAmount(pointsToEarn, context: context, comment: "Task completed: \(task.title) (via activity: \(name))")
                    print("🎁 Earned \(pointsToEarn) points from reward '\(reward.name)' for completing task '\(task.title)'")
                }
            }
        } else {
            // No reward links - add to Unclaimed Points
            let pointsToEarn = task.effectiveWeight
            Reward.addUnclaimedPoints(pointsToEarn, context: context)
            print("🎁 Added \(pointsToEarn) points to Unclaimed Points for completing task '\(task.title)' (via activity: \(name))")
        }
    }
}

enum RewardBurnType: String, Codable, CaseIterable {
    case time = "time"
    case money = "money"
    case points = "points"
    
    var displayName: String {
        switch self {
        case .time:
            return "Time (minutes)"
        case .money:
            return "Money (dollars)"
        case .points:
            return "Points"
        }
    }
    
    var unit: String {
        switch self {
        case .time:
            return "min"
        case .money:
            return "$"
        case .points:
            return "pts"
        }
    }
    
    var icon: String {
        switch self {
        case .time:
            return "clock.fill"
        case .money:
            return "dollarsign.circle.fill"
        case .points:
            return "star.fill"
        }
    }
}

@Model
class ActivityUsageHistory {
    var activityName: String
    var usedAt: Date
    var windowStartTime: Date
    var windowEndTime: Date
    var notes: String?
    var usageType: ActivityUsageType? // Track if this was regular window use or credit use - optional for migration
    var creditsUsed: Int? // Number of credits used (only for credit usage)
    
    init(activityName: String, usedAt: Date = Date(), windowStartTime: Date, windowEndTime: Date, notes: String? = nil, usageType: ActivityUsageType = .regularWindow, creditsUsed: Int? = nil) {
        self.activityName = activityName
        self.usedAt = usedAt
        self.windowStartTime = windowStartTime
        self.windowEndTime = windowEndTime
        self.notes = notes
        self.usageType = usageType
        self.creditsUsed = creditsUsed
    }
    
    // Get the effective usage type (with migration fallback)
    var effectiveUsageType: ActivityUsageType {
        return usageType ?? .regularWindow
    }
    
    // Migration helper for existing usage history
    func ensureMigration() {
        if usageType == nil {
            usageType = .regularWindow
            print("🔄 Migrated usage history for '\(activityName)' to regular window type")
        }
    }
}

enum ActivityUsageType: String, Codable, CaseIterable {
    case regularWindow = "Regular Window"
    case creditUsage = "Credit Usage"
    
    var displayName: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .regularWindow:
            return "clock.fill"
        case .creditUsage:
            return "gift.fill"
        }
    }
}