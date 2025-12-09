import Foundation
import SwiftData

@Model
class RewardSpendEntry {
    var id: UUID
    var amount: Double
    var date: Date
    var comment: String
    var reward: Reward?
    
    init(amount: Double, comment: String = "", reward: Reward) {
        self.id = UUID()
        self.amount = amount
        self.date = Date()
        self.comment = comment
        self.reward = reward
    }
}

@Model
class RewardTransaction {
    var id: UUID
    var amount: Double
    var type: TransactionType
    var date: Date
    var reward: Reward?
    var taskTitle: String? // Track which task contributed points
    var comment: String? // Comment for burns
    
    enum TransactionType: String, Codable {
        case add
        case burn
    }
    
    init(amount: Double, type: TransactionType, reward: Reward, taskTitle: String? = nil, comment: String? = nil) {
        self.id = UUID()
        self.amount = amount
        self.type = type
        self.date = Date()
        self.reward = reward
        self.taskTitle = taskTitle
        self.comment = comment
    }
}

@Model
class Reward {
    var id: UUID
    var name: String
    var type: RewardType
    var currentAmount: Double  // Current points earned
    var goalAmount: Double? // Points needed to unlock reward (for goal-based) or points for conversion
    var rewardValue: Double? // The base reward value (minutes, money amount, etc.)
    var additionalPointsEarned: Double? // Extra points earned beyond goal
    var rewardSpent: Double? // Track how much of the reward has been spent/used
    var rewardDescription: String?
    var status: RewardStatus?
    var createdDate: Date
    var lastModified: Date
    var lastUtilizedDate: Date?
    
    // New properties for the three reward types
    var conversionRate: Double? // For time/money: how many minutes/dollars per point (e.g., 5 minutes per point)
    var endDate: Date? // For goal-based rewards: deadline to reach the goal
    
    // Overdraft properties
    var allowOverdraft: Bool = false // Allow burning more than available
    var overdraftAmount: Double = 0.0 // Current overdraft (negative balance)
    var interestRate: Double? // Interest rate per period (e.g., 10% = 0.10)
    var interestPeriodDays: Int? // Period in days for interest calculation (e.g., 5 days)
    var lastInterestDate: Date? // Last time interest was calculated
    
    @Relationship(deleteRule: .cascade, inverse: \RewardTransaction.reward)
    var transactions: [RewardTransaction] = []
    
    @Relationship(deleteRule: .cascade, inverse: \TaskRewardLink.reward)
    var taskLinks: [TaskRewardLink] = []
    
    @Relationship(deleteRule: .cascade, inverse: \RewardSpendEntry.reward)
    var spendHistory: [RewardSpendEntry] = []
    
    init(name: String, type: RewardType, goalAmount: Double? = nil, rewardValue: Double? = nil, description: String? = nil, conversionRate: Double? = nil, endDate: Date? = nil, allowOverdraft: Bool = false, interestRate: Double? = nil, interestPeriodDays: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.currentAmount = 0.0
        self.goalAmount = goalAmount
        self.rewardValue = rewardValue
        self.additionalPointsEarned = 0.0
        self.rewardSpent = 0.0
        self.rewardDescription = description
        self.status = .needPoints
        self.createdDate = Date()
        self.lastModified = Date()
        self.conversionRate = conversionRate
        self.endDate = endDate
        self.allowOverdraft = allowOverdraft
        self.overdraftAmount = 0.0
        self.interestRate = interestRate
        self.interestPeriodDays = interestPeriodDays
        self.lastInterestDate = nil
    }
    
    // Computed property for reward status
    var computedStatus: RewardStatus {
        // If status is explicitly set, use it (unless it's nil, then compute)
        if let currentStatus = status {
            if currentStatus == .utilized {
                return .utilized
            }
        }
        
        // Time-based and money-based rewards are always ready (no unlocking needed)
        if type == .timeReward || type == .moneyReward {
            return .readyToUse
        }
        
        // Goal-based rewards need to reach their goal
        if type == .goalReward, let goal = goalAmount {
            return currentAmount >= goal ? .readyToUse : .needPoints
        }
        
        return .readyToUse // Default to ready
    }
    
    // Progress percentage
    var progressPercentage: Double {
        guard let goal = goalAmount, goal > 0 else { return 100 }
        return min((currentAmount / goal) * 100, 100)
    }
    
    // Points remaining to goal
    var pointsRemaining: Double {
        guard let goal = goalAmount else { return 0 }
        return max(goal - currentAmount, 0)
    }
    
    // Conversion ratio: reward value per point
    var pointsToValueRatio: Double? {
        guard let goal = goalAmount, goal > 0, let value = rewardValue, value > 0 else { return nil }
        return value / goal
    }
    
    // Additional reward value from extra points
    var additionalRewardValue: Double {
        guard let ratio = pointsToValueRatio, let extraPoints = additionalPointsEarned else { return 0 }
        return extraPoints * ratio
    }
    
    // Total reward value (base + additional)
    var totalRewardValue: Double {
        let base = rewardValue ?? 0
        return base + additionalRewardValue
    }
    
    // Remaining value after spending
    var remainingValue: Double {
        let spent = rewardSpent ?? 0.0
        return max(0, totalRewardValue - spent)
    }
    
    // Helper to get spent amount with default
    var spentAmount: Double {
        return rewardSpent ?? 0.0
    }
    
    // Computed value based on conversion rate (for time/money rewards)
    var convertedValue: Double {
        guard let rate = conversionRate else { return 0 }
        return currentAmount * rate
    }
    
    // Days remaining until end date (for goal-based rewards)
    var daysRemaining: Int? {
        guard let endDate = endDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.day], from: now, to: endDate)
        return components.day
    }
    
    // Check if goal deadline has passed
    var isOverdue: Bool {
        guard let days = daysRemaining else { return false }
        return days < 0
    }
    
    // Check if currently in overdraft
    var isInOverdraft: Bool {
        return overdraftAmount > 0
    }
    
    // Total debt including interest
    var totalDebt: Double {
        return overdraftAmount
    }
    
    // Available balance (can be negative if in overdraft)
    var availableBalance: Double {
        return currentAmount - overdraftAmount
    }
    
    // Converted overdraft value (for time/money rewards)
    var convertedOverdraftValue: Double {
        guard let rate = conversionRate else { return overdraftAmount }
        return overdraftAmount * rate
    }
    
    // Format overdraft amount according to reward type
    func formattedOverdraftAmount() -> String {
        if type == .timeReward, let rate = conversionRate {
            let totalMinutes = overdraftAmount * rate
            let hours = Int(totalMinutes) / 60
            let minutes = Int(totalMinutes) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m (\(String(format: "%.1f", overdraftAmount)) pts)"
            } else {
                return "\(Int(totalMinutes)) min (\(String(format: "%.1f", overdraftAmount)) pts)"
            }
        } else if type == .moneyReward, let rate = conversionRate {
            return "$\(String(format: "%.2f", overdraftAmount * rate)) (\(String(format: "%.1f", overdraftAmount)) pts)"
        }
        return formattedAmount(overdraftAmount)
    }
    
    func addAmount(_ amount: Double, context: ModelContext, taskTitle: String? = nil, comment: String? = nil) {
        var remainingAmount = amount
        
        // First, pay off any overdraft
        if isInOverdraft && remainingAmount > 0 {
            let paymentAmount = min(remainingAmount, overdraftAmount)
            overdraftAmount -= paymentAmount
            remainingAmount -= paymentAmount
            
            print("💳 Paid \(paymentAmount) pts toward overdraft. Remaining overdraft: \(overdraftAmount)")
            
            // If fully paid off, clear interest tracking
            if overdraftAmount <= 0 {
                overdraftAmount = 0.0
                lastInterestDate = nil
                print("✅ Overdraft fully paid off!")
            }
        }
        
        // Add remaining amount to current balance
        currentAmount += remainingAmount
        lastModified = Date()
        
        // Auto-update status if goal is reached (only for goal-based rewards)
        if type == .goalReward, let goal = goalAmount, currentAmount >= goal, status != .utilized {
            status = .readyToUse
            
            // Track additional points earned beyond goal
            let extraPoints = currentAmount - goal
            if extraPoints > 0 {
                additionalPointsEarned = (additionalPointsEarned ?? 0) + extraPoints
            }
        } else if type == .goalReward, let goal = goalAmount, currentAmount > goal {
            // Already past goal, all new points are additional
            additionalPointsEarned = (additionalPointsEarned ?? 0) + remainingAmount
        }
        
        // Generate automatic comment if task title is provided and no manual comment
        let finalComment: String?
        if let taskTitle = taskTitle, comment == nil {
            finalComment = "Completed: \(taskTitle) (+\(String(format: "%.1f", amount)) pts)"
        } else {
            finalComment = comment
        }
        
        let transaction = RewardTransaction(amount: amount, type: .add, reward: self, taskTitle: taskTitle, comment: finalComment)
        context.insert(transaction)
    }
    
    func burnAmount(_ amount: Double, context: ModelContext, comment: String = "") {
        // For time-based and money-based rewards, burn from points directly
        if type == .timeReward || type == .moneyReward {
            // Check if we have enough points
            if currentAmount >= amount {
                // Normal burn
                currentAmount -= amount
            } else if allowOverdraft {
                // Overdraft: burn what we have and track the rest as debt
                let shortfall = amount - currentAmount
                currentAmount = 0.0
                overdraftAmount += shortfall
                
                // Set last interest date if this is the first overdraft
                if lastInterestDate == nil {
                    lastInterestDate = Date()
                }
            } else {
                // Not enough points and overdraft not allowed
                print("⚠️ Cannot burn \(amount) points. Only \(currentAmount) available and overdraft not allowed.")
                return
            }
        } else if type == .guiltReward || name == "Unclaimed Points" {
            // For Guilt and Unclaimed Points, burn from currentAmount (points)
            currentAmount -= amount
        } else {
            // For goal-based rewards, only track spending
            let currentSpent = rewardSpent ?? 0.0
            rewardSpent = currentSpent + amount
        }
        
        lastModified = Date()
        let transaction = RewardTransaction(amount: amount, type: .burn, reward: self, comment: comment)
        context.insert(transaction)
        
        // Add to spend history with comment
        let spendEntry = RewardSpendEntry(amount: amount, comment: comment, reward: self)
        context.insert(spendEntry)
    }
    
    // Check if reward is fully spent and can be reset
    var canReset: Bool {
        let spent = rewardSpent ?? 0.0
        return spent >= totalRewardValue
    }
    
    func utilizeReward(context: ModelContext) {
        guard computedStatus == .readyToUse else { return }
        status = .utilized
        lastUtilizedDate = Date()
        lastModified = Date()
    }
    
    func resetReward(context: ModelContext) {
        status = .needPoints
        currentAmount = 0.0
        additionalPointsEarned = 0.0
        rewardSpent = 0.0
        overdraftAmount = 0.0
        lastInterestDate = nil
        lastModified = Date()
    }
    
    // Calculate and apply interest on overdraft
    func calculateInterest(context: ModelContext) {
        // Only apply interest if in overdraft and interest is configured
        guard isInOverdraft,
              let rate = interestRate,
              let periodDays = interestPeriodDays,
              let lastDate = lastInterestDate else {
            return
        }
        
        let calendar = Calendar.current
        let now = Date()
        let daysSinceLastInterest = calendar.dateComponents([.day], from: lastDate, to: now).day ?? 0
        
        // Calculate how many complete periods have passed
        let completePeriods = daysSinceLastInterest / periodDays
        
        if completePeriods > 0 {
            // Apply compound interest for each complete period
            for _ in 0..<completePeriods {
                let interest = overdraftAmount * rate
                overdraftAmount += interest
                
                // Create a transaction for the interest
                let interestComment = "Interest charged: \(String(format: "%.1f%%", rate * 100)) for \(periodDays) days"
                let transaction = RewardTransaction(amount: interest, type: .burn, reward: self, comment: interestComment)
                context.insert(transaction)
            }
            
            // Update last interest date to the last complete period
            if let newDate = calendar.date(byAdding: .day, value: completePeriods * periodDays, to: lastDate) {
                lastInterestDate = newDate
            }
            
            lastModified = Date()
            print("💰 Applied \(completePeriods) period(s) of interest. New overdraft: \(overdraftAmount)")
        }
    }
    
    // Pay off overdraft with points
    func payOffOverdraft(_ amount: Double, context: ModelContext) {
        guard isInOverdraft else { return }
        
        let paymentAmount = min(amount, overdraftAmount)
        overdraftAmount -= paymentAmount
        
        // If fully paid off, clear interest tracking
        if overdraftAmount <= 0 {
            overdraftAmount = 0.0
            lastInterestDate = nil
        }
        
        lastModified = Date()
        
        let comment = "Overdraft payment: \(String(format: "%.1f", paymentAmount)) pts"
        let transaction = RewardTransaction(amount: paymentAmount, type: .add, reward: self, comment: comment)
        context.insert(transaction)
    }
    
    func todayTotal() -> Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return transactions
            .filter { calendar.startOfDay(for: $0.date) == today }
            .reduce(0) { total, transaction in
                switch transaction.type {
                case .add:
                    return total + transaction.amount
                case .burn:
                    return total - transaction.amount
                }
            }
    }
    
    func allTimeTotal() -> Double {
        return transactions.reduce(0) { total, transaction in
            switch transaction.type {
            case .add:
                return total + transaction.amount
            case .burn:
                return total - transaction.amount
            }
        }
    }
    
    func formattedAmount(_ amount: Double? = nil) -> String {
        let value = amount ?? currentAmount
        return String(format: "%.1f pts", value)
    }
    
    func formattedRewardValue() -> String {
        guard let value = rewardValue else { return "Not set" }
        return formatValue(value)
    }
    
    func formattedTotalValue() -> String {
        return formatValue(totalRewardValue)
    }
    
    func formattedAdditionalValue() -> String {
        return formatValue(additionalRewardValue)
    }
    
    private func formatValue(_ value: Double) -> String {
        switch type {
        case .timeReward, .time:
            // For time rewards, show converted minutes
            if let rate = conversionRate {
                let totalMinutes = value * rate
                let hours = Int(totalMinutes) / 60
                let minutes = Int(totalMinutes) % 60
                if hours > 0 {
                    return "\(hours)h \(minutes)m"
                } else {
                    return "\(Int(totalMinutes)) min"
                }
            }
            return String(format: "%.1f pts", value)
        case .moneyReward:
            // For money rewards, show converted money
            if let rate = conversionRate {
                return String(format: "$%.2f", value * rate)
            }
            return String(format: "%.1f pts", value)
        case .goalReward, .eventReward:
            // For goal rewards, just show points
            return String(format: "%.1f pts", value)
        case .guiltReward:
            return String(format: "$%.2f", value)
        default:
            return String(format: "%.1f", value)
        }
    }
    
    // Static helper to add points to Unclaimed Points reward
    static func addUnclaimedPoints(_ points: Double, context: ModelContext) {
        print("🎯 Adding \(points) points to Unclaimed Points")
        
        let descriptor = FetchDescriptor<Reward>(
            predicate: #Predicate { $0.name == "Unclaimed Points" }
        )
        
        do {
            let rewards = try context.fetch(descriptor)
            if let unclaimedReward = rewards.first {
                print("✅ Found existing Unclaimed Points reward with \(unclaimedReward.currentAmount) points")
                unclaimedReward.addAmount(points, context: context)
                print("✅ Updated to \(unclaimedReward.currentAmount) points")
                try context.save()
                print("✅ Saved successfully")
            } else {
                print("⚠️ Unclaimed Points reward not found, creating new one")
                // Create the reward if it doesn't exist
                let newReward = Reward(name: "Unclaimed Points", type: .smallReward)
                newReward.addAmount(points, context: context)
                context.insert(newReward)
                try context.save()
                print("✅ Created and saved new Unclaimed Points reward with \(newReward.currentAmount) points")
            }
        } catch {
            print("❌ Failed to add unclaimed points: \(error)")
        }
    }
}

enum RewardType: String, CaseIterable, Codable {
    case timeReward = "timeReward"      // Time-based: points convert to minutes
    case moneyReward = "moneyReward"    // Money-based: points convert to money
    case goalReward = "goalReward"      // Goal-based: accumulate points with deadline
    case guiltReward = "guiltReward"    // Track unplanned spending/rewards
    
    // Legacy values for backward compatibility
    case eventReward = "eventReward"
    case smallReward = "small"
    case bigReward = "big"
    case count = "count"
    case time = "time"
    
    var displayName: String {
        switch self {
        case .timeReward:
            return "Time-Based"
        case .moneyReward:
            return "Money-Based"
        case .goalReward:
            return "Goal-Based"
        case .guiltReward:
            return "Guilt Reward"
        // Legacy mappings
        case .eventReward:
            return "Goal-Based"
        case .smallReward, .count:
            return "Time-Based"
        case .bigReward, .time:
            return "Goal-Based"
        }
    }
    
    var unit: String {
        switch self {
        case .timeReward, .time:
            return "points"
        case .moneyReward:
            return "points"
        case .goalReward, .eventReward:
            return "points"
        case .guiltReward:
            return "guilt"
        case .smallReward, .bigReward, .count:
            return "points"
        }
    }
    
    var icon: String {
        switch self {
        case .timeReward, .time:
            return "clock.fill"
        case .moneyReward:
            return "dollarsign.circle.fill"
        case .goalReward, .eventReward:
            return "target"
        case .guiltReward:
            return "exclamationmark.triangle.fill"
        case .smallReward, .bigReward, .count:
            return "gift.fill"
        }
    }
    
    // Helper to get the modern equivalent
    var modernType: RewardType {
        switch self {
        case .count, .smallReward:
            return .timeReward
        case .time, .bigReward, .eventReward:
            return .goalReward
        default:
            return self
        }
    }
    
    // Only show modern types in picker
    static var modernCases: [RewardType] {
        return [.timeReward, .moneyReward, .goalReward, .guiltReward]
    }
    
    // Can this reward type be burned?
    var canBurn: Bool {
        switch self {
        case .timeReward, .moneyReward, .guiltReward, .goalReward:
            return true
        default:
            return true
        }
    }
}

enum RewardStatus: String, CaseIterable, Codable {
    case needPoints = "Need Points"
    case readyToUse = "Ready to Use"
    case utilized = "Utilized"
    
    var color: String {
        switch self {
        case .needPoints: return "orange"
        case .readyToUse: return "green"
        case .utilized: return "gray"
        }
    }
}

// Link between tasks and rewards for workflow automation
@Model
class TaskRewardLink {
    var id: UUID
    var task: Task?
    var reward: Reward?
    var createdDate: Date
    var isActive: Bool
    
    // Computed property to get points from task's effective weight (proportional to time spent)
    var pointsToAdd: Double {
        return task?.effectiveWeight ?? 0.0
    }
    
    init(task: Task, reward: Reward) {
        self.id = UUID()
        self.task = task
        self.reward = reward
        self.createdDate = Date()
        self.isActive = true
    }
}