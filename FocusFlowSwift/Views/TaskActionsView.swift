import SwiftUI
import SwiftData

struct TaskRewardActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reward.name) private var allRewards: [Reward]
    
    @Bindable var task: Task
    var onTaskDeleted: () -> Void
    
    @State private var showAddRewardLink = false
    @State private var showDeleteConfirmation = false
    @State private var linkToDelete: TaskRewardLink?
    
    var activeRewardLinks: [TaskRewardLink] {
        task.rewardLinks?.filter { $0.isActive } ?? []
    }
    
    var body: some View {
        NavigationView {
            List {
                // Task Info Section
                Section("Task Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title)
                            .font(.headline)
                        
                        if !task.taskDescription.isEmpty {
                            Text(task.taskDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Label("Weight: \(String(format: "%.1f", task.weight))", systemImage: "star.fill")
                                .font(.caption)
                            
                            Spacer()
                            
                            if task.completed {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                
                // Reward Workflows Section
                Section {
                    if activeRewardLinks.isEmpty {
                        ContentUnavailableView(
                            "No Reward Workflows",
                            systemImage: "gift.fill",
                            description: Text("Add rewards to automatically earn points when this task is completed")
                        )
                    } else {
                        ForEach(activeRewardLinks) { link in
                            RewardLinkRow(link: link, onDelete: {
                                linkToDelete = link
                                showDeleteConfirmation = true
                            })
                        }
                    }
                } header: {
                    HStack {
                        Text("Reward Workflows")
                        Spacer()
                        Button {
                            showAddRewardLink = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                } footer: {
                    Text("When this task is completed, points will be automatically added to the linked rewards")
                }
                
                // Quick Actions Section
                Section("Quick Actions") {
                    Button {
                        processTaskCompletion()
                    } label: {
                        Label("Complete & Add Points", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .disabled(task.completed || activeRewardLinks.isEmpty)
                    
                    Button {
                        task.completed = false
                        try? modelContext.save()
                    } label: {
                        Label("Mark as Incomplete", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!task.completed)
                }
                
                // Delete Task
                Section {
                    Button(role: .destructive) {
                        modelContext.delete(task)
                        try? modelContext.save()
                        onTaskDeleted()
                        dismiss()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Task Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddRewardLink) {
                AddRewardLinkView(task: task, availableRewards: allRewards)
            }
            .alert("Delete Workflow", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let link = linkToDelete {
                        link.isActive = false
                        try? modelContext.save()
                    }
                }
            } message: {
                Text("Are you sure you want to remove this reward workflow?")
            }
        }
    }
    
    private func processTaskCompletion() {
        task.completed = true
        
        if !activeRewardLinks.isEmpty {
            // Add points to all linked rewards
            print("🎁 Task has \(activeRewardLinks.count) reward link(s)")
            for link in activeRewardLinks {
                if let reward = link.reward {
                    print("➕ Adding \(link.pointsToAdd) points to '\(reward.name)'")
                    reward.addAmount(link.pointsToAdd, context: modelContext, taskTitle: task.title)
                }
            }
        } else {
            // No reward links - add to Unclaimed Points
            print("➕ No reward links, adding \(task.effectiveWeight) points to Unclaimed Points")
            Reward.addUnclaimedPoints(task.effectiveWeight, context: modelContext)
        }
        
        try? modelContext.save()
    }
}

struct RewardLinkRow: View {
    let link: TaskRewardLink
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.reward?.name ?? "Unknown Reward")
                    .font(.headline)
                
                Text("\(String(format: "%.1f", link.pointsToAdd)) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let reward = link.reward {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(reward.computedStatus.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(reward.computedStatus))
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                    
                    if let goal = reward.goalAmount {
                        Text("\(String(format: "%.0f", reward.currentAmount))/\(String(format: "%.0f", goal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
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

struct AddRewardLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let task: Task
    let availableRewards: [Reward]
    
    @State private var selectedReward: Reward?
    @State private var showCreateReward = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Select Reward") {
                    if availableRewards.isEmpty {
                        Text("No rewards available")
                            .foregroundStyle(.secondary)
                        
                        Button("Create New Reward") {
                            showCreateReward = true
                        }
                    } else {
                        Picker("Reward", selection: $selectedReward) {
                            Text("Select a reward").tag(nil as Reward?)
                            ForEach(availableRewards) { reward in
                                Text(reward.name).tag(reward as Reward?)
                            }
                        }
                        
                        Button("Create New Reward") {
                            showCreateReward = true
                        }
                    }
                }
                
                if let reward = selectedReward {
                    Section("Reward Info") {
                        HStack {
                            Text("Current:")
                            Spacer()
                            Text(reward.formattedAmount())
                        }
                        
                        if let goal = reward.goalAmount {
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
                        }
                        
                        HStack {
                            Text("Status:")
                            Spacer()
                            Text(reward.computedStatus.rawValue)
                                .foregroundStyle(statusColor(reward.computedStatus))
                        }
                    }
                }
                
                Section("Points from Task") {
                    HStack {
                        Text("Base Weight:")
                        Spacer()
                        Text(String(format: "%.1f pts", task.weight))
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    
                    if let timeSpent = task.timeSpent, task.allocatedTimeInMinutes > 0 {
                        HStack {
                            Text("Time Spent:")
                            Spacer()
                            Text(String(format: "%.0f / %.0f min", timeSpent, task.allocatedTimeInMinutes))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Effective Points:")
                            Spacer()
                            Text(String(format: "%.1f pts", task.effectiveWeight))
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Text("Points are proportional to time spent. Complete the full allocated time to earn all points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Reward Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveRewardLink()
                    }
                    .disabled(selectedReward == nil || task.weight <= 0)
                }
            }
            .sheet(isPresented: $showCreateReward) {
                AddRewardView()
            }
        }
    }
    
    private func saveRewardLink() {
        guard let reward = selectedReward,
              task.weight > 0 else { return }
        
        let link = TaskRewardLink(task: task, reward: reward)
        modelContext.insert(link)
        
        try? modelContext.save()
        dismiss()
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Task.self, Reward.self, configurations: config)
    let context = container.mainContext
    
    let task = Task(title: "Sample Task", weight: 10.0)
    context.insert(task)
    
    return TaskRewardActionsView(task: task, onTaskDeleted: {})
        .modelContainer(container)
}
