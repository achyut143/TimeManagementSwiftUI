import SwiftUI
import SwiftData

struct RewardHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let reward: Reward
    
    @State private var editingEntry: RewardSpendEntry?
    @State private var showingAddComment = false
    @State private var currentWeekOffset: Int = 0 // 0 = current week, -1 = last week, etc.
    
    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }
    
    private var currentWeekRange: (start: Date, end: Date) {
        let today = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: calendar.date(byAdding: .weekOfYear, value: currentWeekOffset, to: today)!))!
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return (weekStart, weekEnd)
    }
    
    private var weekSpendHistory: [RewardSpendEntry] {
        let range = currentWeekRange
        return reward.spendHistory.filter { entry in
            entry.date >= range.start && entry.date <= calendar.date(byAdding: .day, value: 1, to: range.end)!
        }.sorted(by: { $0.date > $1.date })
    }
    
    private var weekTransactions: [RewardTransaction] {
        let range = currentWeekRange
        return reward.transactions.filter { transaction in
            transaction.date >= range.start && transaction.date <= calendar.date(byAdding: .day, value: 1, to: range.end)!
        }
    }
    
    private var weekMetrics: (adds: Int, burns: Int, totalAdded: Double, totalBurned: Double) {
        var adds = 0
        var burns = 0
        var totalAdded = 0.0
        var totalBurned = 0.0
        
        for transaction in weekTransactions {
            switch transaction.type {
            case .add:
                adds += 1
                totalAdded += transaction.amount
            case .burn:
                burns += 1
                totalBurned += transaction.amount
            }
        }
        
        return (adds, burns, totalAdded, totalBurned)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Week Navigation
                HStack {
                    Button(action: {
                        withAnimation {
                            currentWeekOffset -= 1
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(weekRangeText())
                            .font(.headline)
                        
                        if currentWeekOffset == 0 {
                            Text("This Week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if currentWeekOffset == -1 {
                            Text("Last Week")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            currentWeekOffset += 1
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            .foregroundStyle(currentWeekOffset >= 0 ? .gray : .blue)
                    }
                    .disabled(currentWeekOffset >= 0)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                // Week Metrics
                HStack(spacing: 20) {
                    VStack {
                        Text("\(weekMetrics.adds)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.green)
                        Text("Adds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(reward.formattedAmount(weekMetrics.totalAdded))
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider()
                        .frame(height: 50)
                    
                    VStack {
                        Text("\(weekMetrics.burns)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        Text("Burns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatSpentAmount(weekMetrics.totalBurned))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                List {
                    // Summary Section (only for current week)
                    if currentWeekOffset == 0 {
                        Section("Reward Summary") {
                    HStack {
                        Text("Base Value")
                        Spacer()
                        Text(reward.formattedRewardValue())
                            .foregroundColor(.secondary)
                    }
                    
                    if let extraPoints = reward.additionalPointsEarned, extraPoints > 0 {
                        HStack {
                            Text("Bonus Value")
                            Spacer()
                            Text(reward.formattedAdditionalValue())
                                .foregroundColor(.green)
                        }
                        
                        HStack {
                            Text("Total Value")
                            Spacer()
                            Text(reward.formattedTotalValue())
                                .font(.headline)
                                .foregroundColor(.purple)
                        }
                    }
                    
                    HStack {
                        Text("Total Spent")
                        Spacer()
                        Text(formatSpentAmount(reward.spentAmount))
                            .foregroundColor(.orange)
                    }
                    
                    HStack {
                        Text("Remaining")
                        Spacer()
                        Text(formatSpentAmount(reward.remainingValue))
                            .foregroundColor(.green)
                    }
                    
                    if reward.canReset {
                        Button(action: {
                            reward.resetReward(context: modelContext)
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset Reward")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                    }
                }
                
                // All Transactions for Selected Week
                Section(currentWeekOffset == 0 ? "This Week's Activity" : "Week Activity") {
                    if weekTransactions.isEmpty {
                        Text("No activity this week")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(weekTransactions.sorted(by: { $0.date > $1.date })) { transaction in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: transaction.type == .add ? "plus.circle.fill" : "flame.fill")
                                        .foregroundColor(transaction.type == .add ? .green : .orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(transaction.type == .add ? "Added" : "Burned")
                                                .font(.headline)
                                            
                                            if let taskTitle = transaction.taskTitle {
                                                Text("• \(taskTitle)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        
                                        Text(transaction.date, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text("\(transaction.type == .add ? "+" : "-")\(formatSpentAmount(transaction.amount))")
                                        .font(.headline)
                                        .foregroundColor(transaction.type == .add ? .green : .orange)
                                }
                                
                                if let comment = transaction.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 24)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Reward History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddComment) {
                if let entry = editingEntry {
                    AddCommentView(entry: entry)
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width < -50 {
                            // Swipe left - go to previous week
                            withAnimation {
                                currentWeekOffset -= 1
                            }
                        } else if value.translation.width > 50 && currentWeekOffset < 0 {
                            // Swipe right - go to next week (if not at current week)
                            withAnimation {
                                currentWeekOffset += 1
                            }
                        }
                    }
            )
        }
    }
    
    private func weekRangeText() -> String {
        let range = currentWeekRange
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        
        let startText = formatter.string(from: range.start)
        let endText = formatter.string(from: range.end)
        
        return "\(startText) - \(endText)"
    }
    
    private func formatSpentAmount(_ amount: Double) -> String {
        switch reward.type {
        case .timeReward, .time:
            // Convert points to minutes using conversion rate
            if let rate = reward.conversionRate {
                let totalMinutes = amount * rate
                let hours = Int(totalMinutes) / 60
                let minutes = Int(totalMinutes) % 60
                if hours > 0 {
                    return "\(hours)h \(minutes)m"
                } else {
                    return "\(Int(totalMinutes)) min"
                }
            } else {
                // Fallback to points if no conversion rate
                return String(format: "%.1f pts", amount)
            }
        case .moneyReward:
            // Convert points to money using conversion rate
            if let rate = reward.conversionRate {
                return String(format: "$%.2f", amount * rate)
            } else {
                // Fallback to points if no conversion rate
                return String(format: "%.1f pts", amount)
            }
        case .eventReward:
            return "1 event"
        case .guiltReward:
            return String(format: "$%.2f", amount)
        default:
            return String(format: "%.1f pts", amount)
        }
    }
}

struct AddCommentView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: RewardSpendEntry
    
    @State private var commentText: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Comment") {
                    TextEditor(text: $commentText)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Add Comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        entry.comment = commentText
                        dismiss()
                    }
                }
            }
            .onAppear {
                commentText = entry.comment
            }
        }
    }
}
