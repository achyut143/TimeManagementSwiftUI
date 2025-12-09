import SwiftUI
import SwiftData

struct EditRewardView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var reward: Reward
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedType: RewardType = .timeReward
    @State private var goalAmount: String = ""
    @State private var conversionRate: String = ""
    @State private var endDate: Date = Date()
    @State private var allowOverdraft: Bool = false
    @State private var interestRate: String = ""
    @State private var interestPeriodDays: String = ""
    
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
            return "How many minutes you earn per point"
        case .moneyReward:
            return "How much money you earn per point"
        default:
            return "Not applicable for this reward type"
        }
    }
    
    var body: some View {
        NavigationStack {
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
                    } header: {
                        Text("Conversion Rate")
                    }
                    
                    Section {
                        Toggle("Allow Overdraft", isOn: $allowOverdraft)
                        
                        if allowOverdraft {
                            TextField("Interest Rate (%)", text: $interestRate)
                                .keyboardType(.decimalPad)
                            
                            TextField("Interest Period (days)", text: $interestPeriodDays)
                                .keyboardType(.numberPad)
                        }
                    } header: {
                        Text("Overdraft Settings")
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
                    } header: {
                        Text("Conversion Rate")
                    }
                    
                    Section {
                        Toggle("Allow Overdraft", isOn: $allowOverdraft)
                        
                        if allowOverdraft {
                            TextField("Interest Rate (%)", text: $interestRate)
                                .keyboardType(.decimalPad)
                            
                            TextField("Interest Period (days)", text: $interestPeriodDays)
                                .keyboardType(.numberPad)
                        }
                    } header: {
                        Text("Overdraft Settings")
                    }
                }
                
                // Goal-Based Reward Settings
                if selectedType == .goalReward {
                    Section {
                        TextField("Goal Amount (points)", text: $goalAmount)
                            .keyboardType(.decimalPad)
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
                    }
                }
                
                Section {
                    HStack {
                        Text("Current Points:")
                        Spacer()
                        Text(reward.formattedAmount())
                            .foregroundStyle(.secondary)
                    }
                    
                    if let rate = reward.conversionRate, reward.currentAmount > 0 {
                        HStack {
                            Text("Converted Value:")
                            Spacer()
                            if reward.type == .timeReward {
                                let totalMinutes = reward.convertedValue
                                let hours = Int(totalMinutes) / 60
                                let minutes = Int(totalMinutes) % 60
                                Text(hours > 0 ? "\(hours)h \(minutes)m" : "\(Int(totalMinutes)) min")
                                    .foregroundStyle(.blue)
                            } else if reward.type == .moneyReward {
                                Text("$\(String(format: "%.2f", reward.convertedValue))")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Text("Current Status")
                }
            }
            .navigationTitle("Edit Reward")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                loadRewardData()
            }
        }
    }
    
    private func loadRewardData() {
        name = reward.name
        description = reward.rewardDescription ?? ""
        selectedType = reward.type.modernType
        goalAmount = reward.goalAmount.map { String($0) } ?? ""
        conversionRate = reward.conversionRate.map { String($0) } ?? ""
        endDate = reward.endDate ?? Date().addingTimeInterval(30 * 24 * 60 * 60)
        allowOverdraft = reward.allowOverdraft
        interestRate = reward.interestRate.map { String($0 * 100) } ?? ""
        interestPeriodDays = reward.interestPeriodDays.map { String($0) } ?? ""
    }
    
    private func saveChanges() {
        reward.name = name
        reward.rewardDescription = description.isEmpty ? nil : description
        reward.type = selectedType
        reward.goalAmount = goalAmount.isEmpty ? nil : Double(goalAmount)
        reward.conversionRate = conversionRate.isEmpty ? nil : Double(conversionRate)
        reward.endDate = selectedType == .goalReward ? endDate : nil
        reward.allowOverdraft = allowOverdraft
        reward.interestRate = allowOverdraft && !interestRate.isEmpty ? (Double(interestRate) ?? 0) / 100.0 : nil
        reward.interestPeriodDays = allowOverdraft && !interestPeriodDays.isEmpty ? Int(interestPeriodDays) : nil
        reward.lastModified = Date()
        
        dismiss()
    }
}
