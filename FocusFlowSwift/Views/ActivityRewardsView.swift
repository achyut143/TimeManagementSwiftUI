import SwiftUI
import SwiftData

struct ActivityRewardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [ScheduledActivity]
    @Environment(\.dismiss) private var dismiss
    
    var activeActivities: [ScheduledActivity] {
        activities.filter { $0.isActive }
    }
    
    var activitiesWithCredits: [ScheduledActivity] {
        activeActivities.filter { $0.accumulatedWindowCredits > 0 }
    }
    
    // Group activities by recurrence type
    var dailyActivities: [ScheduledActivity] {
        activitiesWithCredits.filter { ($0.recurrenceType ?? .daily) == .daily }
    }
    
    var weeklyActivities: [ScheduledActivity] {
        activitiesWithCredits.filter { ($0.recurrenceType ?? .daily) == .weekly }
    }
    
    var monthlyActivities: [ScheduledActivity] {
        activitiesWithCredits.filter { ($0.recurrenceType ?? .daily) == .monthly }
    }
    
    var quarterlyActivities: [ScheduledActivity] {
        activitiesWithCredits.filter { ($0.recurrenceType ?? .daily) == .quarterly }
    }
    
    var totalWindowCredits: Int {
        activeActivities.reduce(0) { $0 + $1.accumulatedWindowCredits }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Total Credits Header
                VStack(spacing: 8) {
                    Text("Total Window Credits")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(formattedCredits(totalWindowCredits))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                
                if !activitiesWithCredits.isEmpty {
                    // Individual Activity Credits
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Daily Activities Section
                            if !dailyActivities.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.blue)
                                        Text("Daily")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(dailyActivities, id: \.name) { activity in
                                        ActivityRewardCard(activity: activity, modelContext: modelContext)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Weekly Activities Section
                            if !weeklyActivities.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "calendar.badge.clock")
                                            .foregroundColor(.green)
                                        Text("Weekly")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(weeklyActivities, id: \.name) { activity in
                                        ActivityRewardCard(activity: activity, modelContext: modelContext)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Monthly Activities Section
                            if !monthlyActivities.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "calendar.circle")
                                            .foregroundColor(.orange)
                                        Text("Monthly")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(monthlyActivities, id: \.name) { activity in
                                        ActivityRewardCard(activity: activity, modelContext: modelContext)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                            
                            // Quarterly Activities Section
                            if !quarterlyActivities.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "calendar.badge.plus")
                                            .foregroundColor(.purple)
                                        Text("Quarterly")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(quarterlyActivities, id: \.name) { activity in
                                        ActivityRewardCard(activity: activity, modelContext: modelContext)
                                            .padding(.horizontal)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Image(systemName: "gift")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No Window Credits Available")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Skip scheduled activity windows to earn credits that you can use later")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Window Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formattedCredits(_ credits: Int) -> String {
        if credits == 1 {
            return "1 window"
        } else {
            return "\(credits) windows"
        }
    }
}

struct ActivityRewardCard: View {
    let activity: ScheduledActivity
    let modelContext: ModelContext
    
    @State private var showUseOptions = false
    @State private var showChart = false
    @State private var showOverdraftSheet = false
    @State private var overdraftWindows = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(activity.name)
                    .font(.headline)
                
                Spacer()
                
                Text(activity.formattedWindowCredits())
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
            
            HStack {
                Text("Windows skipped in period: \(activity.windowsSkippedInPeriod)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Windows used in period: \(activity.windowsUsedInPeriod)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if activity.overdraftWindowsUsed > 0 {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Overdraft used: \(activity.overdraftWindowsUsed)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            // Chart button
            Button {
                showChart = true
            } label: {
                HStack {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption)
                    Text("View Chart")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            
            // Always show use/overdraft buttons
            HStack(spacing: 8) {
                if activity.accumulatedWindowCredits >= 1 {
                    // Use buttons for credits
                    Button {
                        if activity.useWindowCredits(1, context: modelContext) {
                            try? modelContext.save()
                        }
                    } label: {
                        Text("Use 1")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    if activity.accumulatedWindowCredits >= 2 {
                        Button {
                            if activity.useWindowCredits(2, context: modelContext) {
                                try? modelContext.save()
                            }
                        } label: {
                            Text("Use 2")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    if activity.accumulatedWindowCredits >= 5 {
                        Button {
                            if activity.useWindowCredits(5, context: modelContext) {
                                try? modelContext.save()
                            }
                        } label: {
                            Text("Use 5")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                
                // Always show overdraft button
                Button {
                    showOverdraftSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption)
                        Text("Overdraft")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            
            // Ignore buttons (second row) - only if credits available
            if activity.accumulatedWindowCredits >= 1 {
                HStack(spacing: 8) {
                    Button {
                        if activity.ignoreWindowCredits(1, context: modelContext) {
                            try? modelContext.save()
                        }
                    } label: {
                        Text("Ignore 1")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    if activity.accumulatedWindowCredits >= 2 {
                        Button {
                            if activity.ignoreWindowCredits(2, context: modelContext) {
                                try? modelContext.save()
                            }
                        } label: {
                            Text("Ignore 2")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    if activity.accumulatedWindowCredits >= 5 {
                        Button {
                            if activity.ignoreWindowCredits(5, context: modelContext) {
                                try? modelContext.save()
                            }
                        } label: {
                            Text("Ignore 5")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showChart) {
            NavigationStack {
                ScrollView {
                    ActivityWindowChartView(activity: activity)
                }
                .navigationTitle(activity.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showChart = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showOverdraftSheet) {
            OverdraftUseView(
                activity: activity,
                overdraftWindows: $overdraftWindows,
                modelContext: modelContext,
                onDismiss: {
                    showOverdraftSheet = false
                }
            )
        }
    }
}

struct OverdraftUseView: View {
    let activity: ScheduledActivity
    @Binding var overdraftWindows: Int
    let modelContext: ModelContext
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Use Overdraft Windows")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(activity.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    Text("Overdraft Windows")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        Button {
                            if overdraftWindows > 1 {
                                overdraftWindows -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                                .foregroundColor(overdraftWindows > 1 ? .red : .gray)
                        }
                        .disabled(overdraftWindows <= 1)
                        
                        Text("\(overdraftWindows)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .frame(minWidth: 60)
                        
                        Button {
                            overdraftWindows += 1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                
                // Show what will happen
                VStack(alignment: .leading, spacing: 8) {
                    if activity.hasRewardAttachment {
                        HStack(spacing: 8) {
                            Image(systemName: activity.effectiveRewardBurnType.icon)
                                .foregroundColor(.purple)
                            Text("Will burn: \(activity.formattedBurnAmount(multiplier: overdraftWindows))")
                                .font(.subheadline)
                        }
                    }
                    
                    if activity.hasTaskAttachment {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.plus.fill")
                                .foregroundColor(.blue)
                            Text("Will add: \(activity.formattedTaskTime(multiplier: overdraftWindows))")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Button {
                        if activity.useOverdraftWindows(overdraftWindows, context: modelContext) {
                            try? modelContext.save()
                        }
                        onDismiss()
                    } label: {
                        Text("Use \(overdraftWindows) Overdraft \(overdraftWindows == 1 ? "Window" : "Windows")")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ActivityRewardsView()
        .modelContainer(for: [ScheduledActivity.self], inMemory: true)
}