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
            
            if activity.accumulatedWindowCredits >= 1 {
                HStack(spacing: 8) {
                    // Use buttons
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
                    
                    Spacer()
                }
                
                // Ignore buttons (second row)
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
                            .background(Color.red)
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
                                .background(Color.red)
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
                                .background(Color.red)
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
    }
}

#Preview {
    ActivityRewardsView()
        .modelContainer(for: [ScheduledActivity.self], inMemory: true)
}