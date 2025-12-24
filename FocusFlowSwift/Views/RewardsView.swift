import SwiftUI
import SwiftData

struct RewardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reward.name) private var allRewards: [Reward]
    @State private var showingAddReward = false
    @State private var selectedReward: Reward?
    @State private var showingManageReward = false
    @State private var selectedFilter: RewardStatus? = nil
    @State private var showGuiltOnly = false
    @State private var searchText = ""
    @State private var currentPage = 0
    let itemsPerPage = 10
    
    var filteredRewards: [Reward] {
        var filtered = allRewards
        
        // Apply guilt filter first
        if showGuiltOnly {
            filtered = filtered.filter { $0.type == .guiltReward }
        }
        
        // Apply status filter
        if let filter = selectedFilter {
            filtered = filtered.filter { $0.computedStatus == filter }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.rewardDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return filtered
    }
    
    var paginatedRewards: [Reward] {
        let startIndex = currentPage * itemsPerPage
        let endIndex = min(startIndex + itemsPerPage, filteredRewards.count)
        
        guard startIndex < filteredRewards.count else { return [] }
        return Array(filteredRewards[startIndex..<endIndex])
    }
    
    var totalPages: Int {
        max(1, Int(ceil(Double(filteredRewards.count) / Double(itemsPerPage))))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Section
            VStack(spacing: 12) {
                TextField("Search rewards...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        FilterButton(
                            title: "All",
                            isSelected: selectedFilter == nil && !showGuiltOnly,
                            count: allRewards.count
                        ) {
                            selectedFilter = nil
                            showGuiltOnly = false
                            currentPage = 0
                        }
                        
                        ForEach(RewardStatus.allCases, id: \.self) { status in
                            let count = allRewards.filter { $0.computedStatus == status }.count
                            FilterButton(
                                title: status.rawValue,
                                isSelected: selectedFilter == status,
                                count: count,
                                color: statusColor(status)
                            ) {
                                selectedFilter = status
                                showGuiltOnly = false
                                currentPage = 0
                            }
                        }
                        
                        // Guilt filter
                        let guiltCount = allRewards.filter { $0.type == .guiltReward }.count
                        FilterButton(
                            title: "Guilt",
                            isSelected: showGuiltOnly,
                            count: guiltCount,
                            color: .red
                        ) {
                            showGuiltOnly = true
                            selectedFilter = nil
                            currentPage = 0
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            // Rewards List
            if filteredRewards.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Rewards Yet" : "No Results",
                    systemImage: "gift",
                    description: Text(searchText.isEmpty ? "Add your first reward to get started!" : "Try adjusting your filters")
                )
            } else {
                List {
                    ForEach(paginatedRewards) { reward in
                        EnhancedRewardRowView(reward: reward) {
                            selectedReward = reward
                            showingManageReward = true
                        }
                    }
                    .onDelete(perform: deleteRewards)
                }
                
                // Pagination Controls
                if totalPages > 1 {
                    HStack {
                        Button {
                            if currentPage > 0 {
                                currentPage -= 1
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentPage == 0)
                        
                        Spacer()
                        
                        Text("Page \(currentPage + 1) of \(totalPages)")
                            .font(.caption)
                        
                        Spacer()
                        
                        Button {
                            if currentPage < totalPages - 1 {
                                currentPage += 1
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentPage >= totalPages - 1)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .navigationTitle("Rewards")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddReward = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddReward) {
            AddRewardView()
        }
        .sheet(isPresented: $showingManageReward) {
            if let reward = selectedReward {
                ManageRewardView(reward: reward)
            }
        }
        .onAppear {
            ensureUnclaimedPointsReward()
        }
    }
    
    private func deleteRewards(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let reward = paginatedRewards[index]
                // Prevent deletion of Unclaimed Points reward
                if reward.name == "Unclaimed Points" {
                    continue
                }
                modelContext.delete(reward)
            }
        }
    }
    
    private func ensureUnclaimedPointsReward() {
        // Check if Unclaimed Points reward already exists
        let hasUnclaimedPoints = allRewards.contains { $0.name == "Unclaimed Points" }
        
        if !hasUnclaimedPoints {
            let unclaimedReward = Reward(name: "Unclaimed Points", type: .smallReward)
            modelContext.insert(unclaimedReward)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to create Unclaimed Points reward: \(error)")
            }
        }
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let count: Int
    var color: Color = .blue
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? color : .gray.opacity(0.2))
            .foregroundStyle(isSelected ? .white : .primary)
            .cornerRadius(16)
        }
    }
}

struct EnhancedRewardRowView: View {
    let reward: Reward
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: reward.type.icon)
                        .font(.title2)
                        .foregroundStyle(iconColor(reward.type))
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reward.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        if let description = reward.rewardDescription {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        
                        HStack(spacing: 4) {
                            Text(reward.type.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            // Show conversion rate for time/money rewards
                            if let rate = reward.conversionRate {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if reward.type == .timeReward {
                                    Text("\(Int(rate)) min/pt")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                } else if reward.type == .moneyReward {
                                    Text("$\(String(format: "%.2f", rate))/pt")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                            
                            // Show available minutes/money to burn for time/money rewards
                            if reward.type == .timeReward, let rate = reward.conversionRate {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let availableMinutes = reward.availableBalance * rate
                                if availableMinutes >= 0 {
                                    Text("+\(Int(availableMinutes)) min")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("\(Int(availableMinutes)) min")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            } else if reward.type == .moneyReward, let rate = reward.conversionRate {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let availableMoney = reward.availableBalance * rate
                                if availableMoney >= 0 {
                                    Text("+$\(String(format: "%.2f", availableMoney))")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("-$\(String(format: "%.2f", abs(availableMoney)))")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            } else if reward.type == .goalReward {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                let availablePoints = reward.availableBalance
                                if availablePoints >= 0 {
                                    Text("+\(String(format: "%.1f", availablePoints)) pts")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("\(String(format: "%.1f", availablePoints)) pts")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }
                            }
                            
                            // Show days remaining for goal-based rewards
                            if reward.type == .goalReward, let days = reward.daysRemaining {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(days)d left")
                                    .font(.caption2)
                                    .foregroundStyle(days < 7 ? .red : .blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(reward.formattedAmount())
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        
                        Text(reward.computedStatus.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(reward.computedStatus))
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Progress bar for rewards with goals
                if let goal = reward.goalAmount {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Goal: \(reward.formattedAmount(goal))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("\(String(format: "%.0f", reward.progressPercentage))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(.gray.opacity(0.2))
                                    .frame(height: 6)
                                
                                Rectangle()
                                    .fill(statusColor(reward.computedStatus))
                                    .frame(width: geometry.size.width * (reward.progressPercentage / 100), height: 6)
                            }
                            .cornerRadius(3)
                        }
                        .frame(height: 6)
                    }
                }
                
                // Show linked tasks count
                let linksCount = reward.taskLinks.filter({ $0.isActive }).count
                if linksCount > 0 {
                    HStack {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text("\(linksCount) task\(linksCount == 1 ? "" : "s") linked")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
    
    private func iconColor(_ type: RewardType) -> Color {
        switch type {
        case .timeReward, .time:
            return .blue
        case .moneyReward:
            return .green
        case .eventReward:
            return .purple
        case .guiltReward:
            return .red
        default:
            return .gray
        }
    }
}

struct RewardRowView: View {
    let reward: Reward
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reward.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(reward.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(reward.formattedAmount())
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Today: \(reward.formattedAmount(reward.todayTotal()))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AddRewardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var selectedType = RewardType.timeReward
    @State private var goalAmount = ""
    @State private var conversionRate = ""
    @State private var endDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days from now
    @State private var allowOverdraft = false
    @State private var interestRate = ""
    @State private var interestPeriodDays = "5"
    
    var conversionRatePlaceholder: String {
        switch selectedType {
        case .timeReward:
            return "Minutes per point (e.g., 5)"
        case .moneyReward:
            return "Dollars per point (e.g., 0.50)"
        default:
            return "Not applicable"
        }
    }
    
    var conversionRateDescription: String {
        switch selectedType {
        case .timeReward:
            return "How many minutes you earn per point (e.g., 1 point = 5 minutes)"
        case .moneyReward:
            return "How much money you earn per point (e.g., 1 point = $0.50)"
        default:
            return "Not applicable for this reward type"
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reward Details") {
                    TextField("Reward Name", text: $name)
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(RewardType.modernCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                }
                
                // Time-Based Reward Settings
                if selectedType == .timeReward {
                    Section {
                        TextField(conversionRatePlaceholder, text: $conversionRate)
                            .keyboardType(.decimalPad)
                        
                        Text(conversionRateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let rate = Double(conversionRate), let goal = Double(goalAmount), rate > 0, goal > 0 {
                            let totalMinutes = goal * rate
                            let hours = Int(totalMinutes) / 60
                            let minutes = Int(totalMinutes) % 60
                            Text("Total reward: \(hours)h \(minutes)m")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    } header: {
                        Text("Conversion Rate")
                    } footer: {
                        Text("Example: If you set 5 minutes per point and earn 10 points, you'll have 50 minutes")
                    }
                    
                    
                    // Overdraft settings for time-based rewards
                    Section {
                        Toggle("Allow Overdraft", isOn: $allowOverdraft)
                        
                        if allowOverdraft {
                            TextField("Interest Rate (%)", text: $interestRate)
                                .keyboardType(.decimalPad)
                            
                            TextField("Interest Period (days)", text: $interestPeriodDays)
                                .keyboardType(.numberPad)
                            
                            if let rate = Double(interestRate), let days = Int(interestPeriodDays), rate > 0, days > 0 {
                                Text("Example: \(String(format: "%.0f%%", rate)) interest every \(days) days")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        Text("Overdraft Settings")
                    } footer: {
                        Text("Allow using more time than earned. Interest will be charged on overdraft amount.")
                    }
                }
                
                // Money-Based Reward Settings
                if selectedType == .moneyReward {
                    Section {
                        TextField(conversionRatePlaceholder, text: $conversionRate)
                            .keyboardType(.decimalPad)
                        
                        Text(conversionRateDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let rate = Double(conversionRate), let goal = Double(goalAmount), rate > 0, goal > 0 {
                            let totalMoney = goal * rate
                            Text("Total reward: $\(String(format: "%.2f", totalMoney))")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } header: {
                        Text("Conversion Rate")
                    } footer: {
                        Text("Example: If you set $0.50 per point and earn 100 points, you'll have $50")
                    }
                    
                    
                    // Overdraft settings for money-based rewards
                    Section {
                        Toggle("Allow Overdraft", isOn: $allowOverdraft)
                        
                        if allowOverdraft {
                            TextField("Interest Rate (%)", text: $interestRate)
                                .keyboardType(.decimalPad)
                            
                            TextField("Interest Period (days)", text: $interestPeriodDays)
                                .keyboardType(.numberPad)
                            
                            if let rate = Double(interestRate), let days = Int(interestPeriodDays), rate > 0, days > 0 {
                                Text("Example: \(String(format: "%.0f%%", rate)) interest every \(days) days")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    } header: {
                        Text("Overdraft Settings")
                    } footer: {
                        Text("Allow spending more money than earned. Interest will be charged on overdraft amount.")
                    }
                }
                
                // Goal-Based Reward Settings
                if selectedType == .goalReward {
                    Section {
                        TextField("Goal Amount (points)", text: $goalAmount)
                            .keyboardType(.decimalPad)
                        
                        Text("Target number of points to reach")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Goal Points")
                    }
                    
                    Section {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                        
                        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
                        Text("\(daysUntil) days remaining")
                            .font(.caption)
                            .foregroundStyle(daysUntil < 7 ? .red : .blue)
                    } header: {
                        Text("Deadline")
                    } footer: {
                        Text("Set a deadline to reach your goal. This helps track progress and stay motivated.")
                    }
                }
                
                // Guilt Reward (keep existing behavior)
                if selectedType == .guiltReward {
                    Section {
                        Text("Guilt rewards track unplanned spending. Just add points as you go.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveReward()
                    }
                    .disabled(name.isEmpty || !isValidReward())
                }
            }
        }
    }
    
    private func isValidReward() -> Bool {
        switch selectedType {
        case .timeReward, .moneyReward:
            // Only require conversion rate, goal is optional
            return !conversionRate.isEmpty && Double(conversionRate) != nil
        case .goalReward:
            return !goalAmount.isEmpty && Double(goalAmount) != nil
        case .guiltReward:
            return true
        default:
            return true
        }
    }
    
    private func saveReward() {
        let desc = description.isEmpty ? nil : description
        let goal = goalAmount.isEmpty ? nil : Double(goalAmount)
        let rate = conversionRate.isEmpty ? nil : Double(conversionRate)
        let end = selectedType == .goalReward ? endDate : nil
        let interest = allowOverdraft && !interestRate.isEmpty ? (Double(interestRate) ?? 0) / 100.0 : nil
        let period = allowOverdraft && !interestPeriodDays.isEmpty ? Int(interestPeriodDays) : nil
        
        let reward = Reward(
            name: name, 
            type: selectedType, 
            goalAmount: goal, 
            rewardValue: nil, 
            description: desc,
            conversionRate: rate,
            endDate: end,
            allowOverdraft: allowOverdraft,
            interestRate: interest,
            interestPeriodDays: period
        )
        modelContext.insert(reward)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save reward: \(error)")
        }
        
        dismiss()
    }
}

struct ManageRewardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var reward: Reward
    @State private var amountToAdd: String = ""
    @State private var addComment: String = ""
    @State private var amountToBurn: String = ""
    @State private var burnComment: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingClearConfirmation = false
    @State private var showTransactions = false
    @State private var showRewardHistory = false
    @State private var showEditReward = false
    @State private var showLinkedTasks = false
    
    var linkedTasks: [TaskRewardLink] {
        reward.taskLinks.filter { $0.isActive }
    }
    
    var burnLabel: String {
        switch reward.type {
        case .timeReward:
            return "Time (minutes)"
        case .moneyReward:
            return "Money"
        case .guiltReward:
            return "Guilt Amount"
        default:
            return "Points"
        }
    }
    
    var burnDescription: String {
        if reward.name == "Unclaimed Points" {
            return "Burn points from unclaimed pool"
        }
        
        switch reward.type {
        case .timeReward:
            if let rate = reward.conversionRate {
                return "Enter minutes to burn (1 point = \(Int(rate)) min). Will be converted to points automatically."
            }
            return "Enter minutes to burn as you use your time"
        case .moneyReward:
            if let rate = reward.conversionRate {
                return "Enter dollars to burn (1 point = $\(String(format: "%.2f", rate))). Will be converted to points automatically."
            }
            return "Enter money to burn as you spend it"
        case .guiltReward:
            return "Burn guilt points to forgive yourself"
        default:
            return "Reduce the reward amount"
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Status Section
                Section("Status") {
                    HStack {
                        Text("Current Status:")
                        Spacer()
                        Text(reward.computedStatus.rawValue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(statusColor(reward.computedStatus))
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                    
                    HStack {
                        Text("Available:")
                        Spacer()
                        Text(reward.formattedAmount())
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    // Show converted value for time/money rewards
                    if let rate = reward.conversionRate, reward.currentAmount > 0 {
                        HStack {
                            Text("Converted Value:")
                            Spacer()
                            if reward.type == .timeReward {
                                let totalMinutes = reward.convertedValue
                                let hours = Int(totalMinutes) / 60
                                let minutes = Int(totalMinutes) % 60
                                if hours > 0 {
                                    Text("\(hours)h \(minutes)m")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("\(Int(totalMinutes)) min")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }
                            } else if reward.type == .moneyReward {
                                Text("$\(String(format: "%.2f", reward.convertedValue))")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    
                    // Show days remaining for goal-based rewards
                    if reward.type == .goalReward, let endDate = reward.endDate {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Deadline:")
                                Spacer()
                                Text(endDate.formatted(date: .abbreviated, time: .omitted))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let days = reward.daysRemaining {
                                HStack {
                                    Text("Days Remaining:")
                                    Spacer()
                                    Text("\(days) days")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(days < 7 ? .red : (days < 14 ? .orange : .blue))
                                }
                                
                                if reward.isOverdue {
                                    Text("⚠️ Goal deadline has passed")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                    
                    if reward.rewardValue != nil && reward.type != .guiltReward && reward.name != "Unclaimed Points" {
                        VStack(spacing: 4) {
                            HStack {
                                Text("Base Reward:")
                                Spacer()
                                Text(reward.formattedRewardValue())
                                    .font(.subheadline)
                                    .foregroundStyle(.blue)
                            }
                            
                            if let extraPoints = reward.additionalPointsEarned, extraPoints > 0 {
                                HStack {
                                    Text("Extra Points:")
                                    Spacer()
                                    Text(reward.formattedAmount(extraPoints))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                HStack {
                                    Text("Bonus Value:")
                                    Spacer()
                                    Text(reward.formattedAdditionalValue())
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            
                            HStack {
                                Text("Total Value:")
                                Spacer()
                                Text(reward.formattedTotalValue())
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    
                    if reward.type == .goalReward, let goal = reward.goalAmount {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Goal:")
                                Spacer()
                                Text(reward.formattedAmount(goal))
                            }
                            
                            HStack {
                                Text("Progress:")
                                Spacer()
                                Text("\(String(format: "%.0f", reward.progressPercentage))%")
                            }
                            
                            if reward.pointsRemaining > 0 {
                                HStack {
                                    Text("Remaining:")
                                    Spacer()
                                    Text(reward.formattedAmount(reward.pointsRemaining))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                
                // Overdraft Section (for time/money rewards)
                if (reward.type == .timeReward || reward.type == .moneyReward) && reward.allowOverdraft {
                    Section("Overdraft") {
                        HStack {
                            Text("Overdraft Amount:")
                            Spacer()
                            Text(reward.formattedOverdraftAmount())
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(reward.isInOverdraft ? .red : .green)
                        }
                        
                        if reward.isInOverdraft {
                            HStack {
                                Text("Available Balance:")
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(reward.formattedAmount(reward.availableBalance))
                                        .foregroundStyle(.red)
                                    if let rate = reward.conversionRate {
                                        if reward.type == .timeReward {
                                            let totalMinutes = reward.availableBalance * rate
                                            let hours = Int(totalMinutes) / 60
                                            let minutes = Int(totalMinutes) % 60
                                            if hours > 0 {
                                                Text("\(hours)h \(minutes)m")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            } else {
                                                Text("\(Int(totalMinutes)) min")
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                        } else if reward.type == .moneyReward {
                                            Text("$\(String(format: "%.2f", reward.availableBalance * rate))")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                            
                            if let rate = reward.interestRate, let days = reward.interestPeriodDays {
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("Interest Rate:")
                                        Spacer()
                                        Text("\(String(format: "%.0f%%", rate * 100)) per \(days) days")
                                            .foregroundStyle(.orange)
                                    }
                                    
                                    if let lastDate = reward.lastInterestDate {
                                        HStack {
                                            Text("Last Interest:")
                                            Spacer()
                                            Text(lastDate.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            Button {
                                // Calculate and apply interest
                                reward.calculateInterest(context: modelContext)
                                try? modelContext.save()
                            } label: {
                                Label("Calculate Interest", systemImage: "percent")
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Text("✅ No overdraft")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                // Actions Section
                if reward.type == .goalReward && reward.computedStatus == .readyToUse {
                    Section("Actions") {
                        Button {
                            reward.utilizeReward(context: modelContext)
                            try? modelContext.save()
                            alertMessage = "Reward '\(reward.name)' has been utilized!"
                            showingAlert = true
                        } label: {
                            Label("Utilize Reward", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                if reward.computedStatus == .utilized {
                    Section("Actions") {
                        Button {
                            reward.resetReward(context: modelContext)
                            try? modelContext.save()
                            alertMessage = "Reward '\(reward.name)' has been reset"
                            showingAlert = true
                        } label: {
                            Label("Reset Reward", systemImage: "arrow.counterclockwise")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                
                // Linked Tasks Summary
                if !linkedTasks.isEmpty {
                    Section("Linked Tasks") {
                        Button {
                            showLinkedTasks = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(linkedTasks.count) task\(linkedTasks.count == 1 ? "" : "s") linked")
                                        .font(.headline)
                                    
                                    let completedCount = linkedTasks.filter { $0.task?.completed == true }.count
                                    Text("\(completedCount) completed, \(linkedTasks.count - completedCount) pending")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // Only show statistics for rewards where burn affects points (Guilt, Unclaimed Points)
                // For other rewards, burn affects reward value, so point statistics aren't meaningful
                if reward.type == .guiltReward || reward.name == "Unclaimed Points" {
                    Section("Statistics") {
                        HStack {
                            Text("Today's Total:")
                            Spacer()
                            Text(reward.formattedAmount(reward.todayTotal()))
                                .foregroundStyle(.blue)
                        }
                        
                        HStack {
                            Text("All-Time Total:")
                            Spacer()
                            Text(reward.formattedAmount(reward.allTimeTotal()))
                                .foregroundStyle(.green)
                        }
                        
                        Button {
                            showTransactions = true
                        } label: {
                            Label("View Transaction History", systemImage: "list.bullet")
                        }
                    }
                }
                
                Section("Add \(reward.type.unit.capitalized)") {
                    HStack {
                        TextField("Amount to add", text: $amountToAdd)
                            .keyboardType(.decimalPad)
                        
                        Button("Add") {
                            addAmount()
                        }
                        .disabled(amountToAdd.isEmpty)
                    }
                    
                    TextField("Comment (optional)", text: $addComment, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                if reward.type.canBurn {
                    Section("Burn \(burnLabel)") {
                        HStack {
                            TextField("Amount to burn", text: $amountToBurn)
                                .keyboardType(.decimalPad)
                            
                            Button("Burn") {
                                burnAmount()
                            }
                            .disabled(amountToBurn.isEmpty)
                            .foregroundStyle(.red)
                        }
                        
                        TextField("Comment (optional)", text: $burnComment, axis: .vertical)
                            .lineLimit(2...4)
                        
                        // Show overdraft warning for time/money rewards
                        if (reward.type == .timeReward || reward.type == .moneyReward) {
                            if let burnAmt = Double(amountToBurn), let rate = reward.conversionRate, rate > 0 {
                                // Convert from minutes/dollars to points
                                let pointsToBurn = burnAmt / rate
                                
                                if pointsToBurn > reward.currentAmount {
                                    if reward.allowOverdraft {
                                        let shortfall = pointsToBurn - reward.currentAmount
                                        if reward.type == .timeReward {
                                            let shortfallMinutes = shortfall * rate
                                            Text("⚠️ This will create an overdraft of \(String(format: "%.1f", shortfall)) pts (\(Int(shortfallMinutes)) min)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        } else {
                                            let shortfallMoney = shortfall * rate
                                            Text("⚠️ This will create an overdraft of \(String(format: "%.1f", shortfall)) pts ($\(String(format: "%.2f", shortfallMoney)))")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    } else {
                                        let availableConverted = reward.currentAmount * rate
                                        if reward.type == .timeReward {
                                            Text("❌ Not enough. Only \(Int(availableConverted)) minutes available.")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        } else {
                                            Text("❌ Not enough. Only $\(String(format: "%.2f", availableConverted)) available.")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Text(burnDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Reward Spent Tracking (for non-guilt rewards)
                if reward.type != .guiltReward && reward.name != "Unclaimed Points" {
                    Section("Reward Spending") {
                        HStack {
                            Text("Total Spent:")
                            Spacer()
                            Text(formatSpentAmount(reward.spentAmount))
                                .foregroundStyle(.orange)
                        }
                        
                        if reward.rewardValue != nil {
                            HStack {
                                Text("Remaining:")
                                Spacer()
                                Text(formatSpentAmount(reward.remainingValue))
                                    .foregroundStyle(.green)
                            }
                            
                            if reward.canReset {
                                Text("✅ Reward fully spent! You can reset it now.")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        Button {
                            showRewardHistory = true
                        } label: {
                            Label("View Spend History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
                
                Section("Details") {
                    if let description = reward.rewardDescription {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(description)
                        }
                    }
                    
                    HStack {
                        Text("Type:")
                        Spacer()
                        Text(reward.type.displayName)
                    }
                    
                    HStack {
                        Text("Created:")
                        Spacer()
                        Text(reward.createdDate.formatted(date: .abbreviated, time: .shortened))
                    }
                    
                    HStack {
                        Text("Last Modified:")
                        Spacer()
                        Text(reward.lastModified.formatted(date: .abbreviated, time: .shortened))
                    }
                    
                    if let utilizedDate = reward.lastUtilizedDate {
                        HStack {
                            Text("Last Utilized:")
                            Spacer()
                            Text(utilizedDate.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Clear Balance")
                            Spacer()
                        }
                    }
                } footer: {
                    Text("This will reset the balance to 0 and delete all transaction history.")
                }
            }
            .navigationTitle(reward.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showEditReward = true
                    } label: {
                        Text("Edit")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Notice", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .alert("Clear Everything", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearBalance()
                }
            } message: {
                Text("This will reset the balance to 0 and delete all transaction history. This cannot be undone.")
            }
            .sheet(isPresented: $showTransactions) {
                TransactionHistoryView(reward: reward)
            }
            .sheet(isPresented: $showRewardHistory) {
                RewardHistoryView(reward: reward)
            }
            .sheet(isPresented: $showEditReward) {
                EditRewardView(reward: reward)
            }
            .sheet(isPresented: $showLinkedTasks) {
                LinkedTasksView(reward: reward)
            }
        }
    }
    
    private func addAmount() {
        guard let amount = Double(amountToAdd), amount > 0 else { return }
        let commentToAdd = addComment.isEmpty ? nil : addComment
        reward.addAmount(amount, context: modelContext, comment: commentToAdd)
        amountToAdd = ""
        addComment = ""
        alertMessage = "Added \(amount) \(reward.type.unit) to \(reward.name)"
        showingAlert = true
    }
    
    private func burnAmount() {
        guard let amount = Double(amountToBurn), amount > 0 else { return }
        
        // Convert from minutes/dollars to points for time/money rewards
        let pointsToBurn: Double
        if reward.type == .timeReward || reward.type == .moneyReward {
            if let rate = reward.conversionRate, rate > 0 {
                // Convert back to points (amount / rate)
                pointsToBurn = amount / rate
            } else {
                // No conversion rate, burn as points
                pointsToBurn = amount
            }
        } else {
            // For other types, burn as-is
            pointsToBurn = amount
        }
        
        reward.burnAmount(pointsToBurn, context: modelContext, comment: burnComment)
        amountToBurn = ""
        burnComment = ""
        
        // Show appropriate message based on type
        if reward.type == .timeReward {
            alertMessage = "Burned \(Int(amount)) minutes (\(String(format: "%.1f", pointsToBurn)) pts) from \(reward.name)"
        } else if reward.type == .moneyReward {
            alertMessage = "Burned $\(String(format: "%.2f", amount)) (\(String(format: "%.1f", pointsToBurn)) pts) from \(reward.name)"
        } else {
            alertMessage = "Burned \(amount) \(reward.type.unit) from \(reward.name)"
        }
        showingAlert = true
    }
    
    private func formatSpentAmount(_ amount: Double) -> String {
        switch reward.type {
        case .timeReward, .time:
            let hours = Int(amount) / 60
            let minutes = Int(amount) % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(Int(amount)) min"
            }
        case .moneyReward:
            return String(format: "$%.2f", amount)
        case .eventReward:
            return "1 event"
        case .guiltReward:
            return String(format: "$%.2f", amount)
        default:
            return String(format: "%.1f", amount)
        }
    }
    
    private func clearBalance() {
        // Delete all transactions
        for transaction in reward.transactions {
            modelContext.delete(transaction)
        }
        
        // Reset balance
        reward.currentAmount = 0.0
        reward.lastModified = Date()
        
        alertMessage = "Balance and transaction history cleared for \(reward.name)"
        showingAlert = true
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
}

struct TransactionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    let reward: Reward
    
    @State private var currentWeekOffset: Int = 0
    
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
    
    private var weekTransactions: [RewardTransaction] {
        let range = currentWeekRange
        return reward.transactions.filter { transaction in
            transaction.date >= range.start && transaction.date <= calendar.date(byAdding: .day, value: 1, to: range.end)!
        }.sorted { $0.date > $1.date }
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
        NavigationView {
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
                        Text(reward.formattedAmount(weekMetrics.totalBurned))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                .background(.ultraThinMaterial)
                
                List {
                    if weekTransactions.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "list.bullet",
                            description: Text("No transactions this week")
                        )
                    } else {
                        ForEach(weekTransactions) { transaction in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(transaction.type == .add ? "Added" : "Burned")
                                            .font(.subheadline)
                                            .foregroundStyle(transaction.type == .add ? .green : .red)
                                        
                                        if let taskTitle = transaction.taskTitle {
                                            Text("• \(taskTitle)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("\(transaction.type == .add ? "+" : "-")\(reward.formattedAmount(transaction.amount))")
                                    .font(.headline)
                                    .foregroundStyle(transaction.type == .add ? .green : .red)
                            }
                            
                            if let comment = transaction.comment, !comment.isEmpty {
                                Text(comment)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                }
            }
            .navigationTitle("Transaction History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        if value.translation.width < -50 {
                            withAnimation {
                                currentWeekOffset -= 1
                            }
                        } else if value.translation.width > 50 && currentWeekOffset < 0 {
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
}

#Preview {
    NavigationStack {
        RewardsView()
    }
    .modelContainer(for: [Reward.self], inMemory: true)
}