import SwiftUI
import SwiftData

struct RewardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reward.name) private var rewards: [Reward]
    @State private var showingAddReward = false
    @State private var selectedReward: Reward?
    @State private var showingManageReward = false
    
    var body: some View {
        List {
            if rewards.isEmpty {
                ContentUnavailableView(
                    "No Rewards Yet",
                    systemImage: "gift",
                    description: Text("Add your first reward to get started!")
                )
            } else {
                ForEach(rewards) { reward in
                    RewardRowView(reward: reward) {
                        selectedReward = reward
                        showingManageReward = true
                    }
                }
                .onDelete(perform: deleteRewards)
            }
        }
        .navigationTitle("Rewards")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add Reward") {
                    showingAddReward = true
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
                let reward = rewards[index]
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
        let hasUnclaimedPoints = rewards.contains { $0.name == "Unclaimed Points" }
        
        if !hasUnclaimedPoints {
            let unclaimedReward = Reward(name: "Unclaimed Points", type: .count)
            modelContext.insert(unclaimedReward)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to create Unclaimed Points reward: \(error)")
            }
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
    @State private var selectedType = RewardType.time
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reward Details") {
                    TextField("Reward Name", text: $name)
                    
                    Picker("Type", selection: $selectedType) {
                        ForEach(RewardType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
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
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveReward() {
        let reward = Reward(name: name, type: selectedType)
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
    @State private var amountToBurn: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingClearConfirmation = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Current Balance") {
                    HStack {
                        Text("Available:")
                        Spacer()
                        Text(reward.formattedAmount())
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                }
                
                Section("Statistics") {
                    HStack {
                        Text("Today's Total:")
                        Spacer()
                        Text(reward.formattedAmount(reward.todayTotal()))
                            .foregroundColor(.blue)
                    }
                    
                    HStack {
                        Text("All-Time Total:")
                        Spacer()
                        Text(reward.formattedAmount(reward.allTimeTotal()))
                            .foregroundColor(.green)
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
                }
                
                Section("Burn \(reward.type.unit.capitalized)") {
                    HStack {
                        TextField("Amount to burn", text: $amountToBurn)
                            .keyboardType(.decimalPad)
                        
                        Button("Burn") {
                            burnAmount()
                        }
                        .disabled(amountToBurn.isEmpty)
                        .foregroundColor(.red)
                    }
                }
                
                Section("Details") {
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
        }
    }
    
    private func addAmount() {
        guard let amount = Double(amountToAdd), amount > 0 else { return }
        reward.addAmount(amount, context: modelContext)
        amountToAdd = ""
        alertMessage = "Added \(amount) \(reward.type.unit) to \(reward.name)"
        showingAlert = true
    }
    
    private func burnAmount() {
        guard let amount = Double(amountToBurn), amount > 0 else { return }
        
        reward.burnAmount(amount, context: modelContext)
        amountToBurn = ""
        alertMessage = "Burned \(amount) \(reward.type.unit) from \(reward.name)"
        showingAlert = true
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
}

#Preview {
    NavigationStack {
        RewardsView()
    }
    .modelContainer(for: [Reward.self], inMemory: true)
}