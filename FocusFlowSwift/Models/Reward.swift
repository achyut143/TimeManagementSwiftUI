import Foundation
import SwiftData

@Model
class RewardTransaction {
    var id: UUID
    var amount: Double
    var type: TransactionType
    var date: Date
    var reward: Reward?
    
    enum TransactionType: String, Codable {
        case add
        case burn
    }
    
    init(amount: Double, type: TransactionType, reward: Reward) {
        self.id = UUID()
        self.amount = amount
        self.type = type
        self.date = Date()
        self.reward = reward
    }
}

@Model
class Reward {
    var id: UUID
    var name: String
    var type: RewardType
    var currentAmount: Double
    var createdDate: Date
    var lastModified: Date
    
    @Relationship(deleteRule: .cascade, inverse: \RewardTransaction.reward)
    var transactions: [RewardTransaction] = []
    
    init(name: String, type: RewardType) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.currentAmount = 0.0
        self.createdDate = Date()
        self.lastModified = Date()
    }
    
    func addAmount(_ amount: Double, context: ModelContext) {
        currentAmount += amount
        lastModified = Date()
        let transaction = RewardTransaction(amount: amount, type: .add, reward: self)
        context.insert(transaction)
    }
    
    func burnAmount(_ amount: Double, context: ModelContext) {
        currentAmount -= amount
        lastModified = Date()
        let transaction = RewardTransaction(amount: amount, type: .burn, reward: self)
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
        switch type {
        case .time:
            let hours = Int(value) / 60
            let minutes = Int(value) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(Int(value))m"
            }
        case .count:
            // Show decimal for count type
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
                let newReward = Reward(name: "Unclaimed Points", type: .count)
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
    case time = "time"
    case count = "count"
    
    var displayName: String {
        switch self {
        case .time:
            return "Time (minutes)"
        case .count:
            return "Count"
        }
    }
    
    var unit: String {
        switch self {
        case .time:
            return "minutes"
        case .count:
            return "points"
        }
    }
}