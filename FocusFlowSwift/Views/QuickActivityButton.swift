import SwiftUI
import SwiftData

struct QuickActivityButton: View {
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive }, sort: \ScheduledActivity.createdAt, order: .reverse)
    private var activities: [ScheduledActivity]
    
    @State private var showActivitiesList = false
    @State private var currentTime = Date()
    @State private var refreshTrigger = UUID()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var hasActiveWindow: Bool {
        activities.contains { $0.isInActiveWindow() }
    }
    
    var totalDailyCredits: Int {
        activities
            .filter { ($0.recurrenceType ?? .daily) == .daily }
            .reduce(0) { $0 + $1.accumulatedWindowCredits }
    }
    
    var nextActivity: (activity: ScheduledActivity, nextTime: Date)? {
        var nextActivityInfo: (activity: ScheduledActivity, nextTime: Date)?
        var earliestTime: Date?
        
        for activity in activities {
            if let nextTime = activity.nextScheduledTime() {
                if earliestTime == nil || nextTime < earliestTime! {
                    earliestTime = nextTime
                    nextActivityInfo = (activity, nextTime)
                }
            }
        }
        
        return nextActivityInfo
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                    // Quick Activities List Button
                    if !activities.isEmpty {
                        Button {
                            refreshTrigger = UUID() // Force refresh when opening
                            showActivitiesList = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                ZStack {
                                    Circle()
                                        .fill(hasActiveWindow ? Color.green : Color.blue)
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                    
                                    Image(systemName: hasActiveWindow ? "clock.badge.checkmark.fill" : "clock.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                
                                // Notification badge for daily credits
                                if totalDailyCredits > 0 {
                                    Text("\(totalDailyCredits)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(Color.orange)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 100) // Above tab bar
            }
        }
        .sheet(isPresented: $showActivitiesList) {
            QuickActivitiesListView(refreshTrigger: refreshTrigger)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

struct QuickActivitiesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive })
    private var activities: [ScheduledActivity]
    
    @State private var currentTime = Date()
    @State private var selectedActivity: ScheduledActivity?
    @State private var showActivityWindow = false
    @State private var showCreditUseSheet = false
    @State private var windowNotes = ""
    @State private var creditsToUse = 1
    @State private var refreshTrigger: UUID
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(refreshTrigger: UUID) {
        _refreshTrigger = State(initialValue: refreshTrigger)
    }
    
    // Sort activities by time remaining (least time first)
    var sortedActivities: [ScheduledActivity] {
        activities.sorted { activity1, activity2 in
            let time1 = timeUntilNext(for: activity1)
            let time2 = timeUntilNext(for: activity2)
            
            // Activities in active window come first (negative time)
            if time1 < 0 && time2 >= 0 {
                return true
            } else if time1 >= 0 && time2 < 0 {
                return false
            } else if time1 < 0 && time2 < 0 {
                // Both in active window, sort by remaining window time (descending)
                return time1 > time2
            } else {
                // Both not in active window, sort by next time (ascending)
                return time1 < time2
            }
        }
    }
    
    // Group activities by recurrence type
    var dailyActivities: [ScheduledActivity] {
        sortedActivities.filter { ($0.recurrenceType ?? .daily) == .daily }
    }
    
    var weeklyActivities: [ScheduledActivity] {
        sortedActivities.filter { ($0.recurrenceType ?? .daily) == .weekly }
    }
    
    var monthlyActivities: [ScheduledActivity] {
        sortedActivities.filter { ($0.recurrenceType ?? .daily) == .monthly }
    }
    
    var quarterlyActivities: [ScheduledActivity] {
        sortedActivities.filter { ($0.recurrenceType ?? .daily) == .quarterly }
    }
    
    private func timeUntilNext(for activity: ScheduledActivity) -> TimeInterval {
        if activity.isInActiveWindow() {
            // Return negative value for active windows (window end time - current time)
            if let windowEnd = activity.currentWindowEndTime() {
                return windowEnd.timeIntervalSince(currentTime)
            }
            return -1
        } else if let nextTime = activity.nextScheduledTime() {
            return nextTime.timeIntervalSince(currentTime)
        }
        return TimeInterval.greatestFiniteMagnitude // Activities with no next time go to the end
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Daily Activities Section
                if !dailyActivities.isEmpty {
                    Section(header: HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.blue)
                        Text("Daily")
                            .font(.headline)
                    }) {
                        ForEach(dailyActivities, id: \.name) { activity in
                            QuickActivityRowView(
                                activity: activity,
                                currentTime: currentTime,
                                onUseWindow: {
                                    selectedActivity = activity
                                    showActivityWindow = true
                                },
                                onUseCredits: {
                                    selectedActivity = activity
                                    creditsToUse = 1
                                    showCreditUseSheet = true
                                }
                            )
                        }
                    }
                }
                
                // Weekly Activities Section
                if !weeklyActivities.isEmpty {
                    Section(header: HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.green)
                        Text("Weekly")
                            .font(.headline)
                    }) {
                        ForEach(weeklyActivities, id: \.name) { activity in
                            QuickActivityRowView(
                                activity: activity,
                                currentTime: currentTime,
                                onUseWindow: {
                                    selectedActivity = activity
                                    showActivityWindow = true
                                },
                                onUseCredits: {
                                    selectedActivity = activity
                                    creditsToUse = 1
                                    showCreditUseSheet = true
                                }
                            )
                        }
                    }
                }
                
                // Monthly Activities Section
                if !monthlyActivities.isEmpty {
                    Section(header: HStack {
                        Image(systemName: "calendar.circle")
                            .foregroundColor(.orange)
                        Text("Monthly")
                            .font(.headline)
                    }) {
                        ForEach(monthlyActivities, id: \.name) { activity in
                            QuickActivityRowView(
                                activity: activity,
                                currentTime: currentTime,
                                onUseWindow: {
                                    selectedActivity = activity
                                    showActivityWindow = true
                                },
                                onUseCredits: {
                                    selectedActivity = activity
                                    creditsToUse = 1
                                    showCreditUseSheet = true
                                }
                            )
                        }
                    }
                }
                
                // Quarterly Activities Section
                if !quarterlyActivities.isEmpty {
                    Section(header: HStack {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundColor(.purple)
                        Text("Quarterly")
                            .font(.headline)
                    }) {
                        ForEach(quarterlyActivities, id: \.name) { activity in
                            QuickActivityRowView(
                                activity: activity,
                                currentTime: currentTime,
                                onUseWindow: {
                                    selectedActivity = activity
                                    showActivityWindow = true
                                },
                                onUseCredits: {
                                    selectedActivity = activity
                                    creditsToUse = 1
                                    showCreditUseSheet = true
                                }
                            )
                        }
                    }
                }
            }
            .id(refreshTrigger) // Force list refresh when trigger changes
            .navigationTitle("Quick Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Force refresh by updating trigger and reloading data
                        refreshTrigger = UUID()
                        try? modelContext.save()
                        currentTime = Date()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showActivityWindow) {
            if let activity = selectedActivity {
                ActivityWindowView(activity: activity, notes: $windowNotes) {
                    recordActivityUsage(activity: activity)
                    showActivityWindow = false
                    selectedActivity = nil
                    windowNotes = ""
                }
            }
        }
        .sheet(isPresented: $showCreditUseSheet) {
            if let activity = selectedActivity {
                CreditUseView(
                    activity: activity,
                    creditsToUse: $creditsToUse,
                    onUse: {
                        if activity.useWindowCredits(creditsToUse, context: modelContext) {
                            try? modelContext.save()
                        }
                        showCreditUseSheet = false
                        selectedActivity = nil
                        creditsToUse = 1
                    },
                    onCancel: {
                        showCreditUseSheet = false
                        selectedActivity = nil
                        creditsToUse = 1
                    }
                )
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onAppear {
            // Refresh data when view appears
            try? modelContext.save()
        }
    }
    
    private func recordActivityUsage(activity: ScheduledActivity) {
        print("🚀 DEBUG: recordActivityUsage called for activity: '\(activity.name)'")
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Burn attached reward if configured
        if activity.burnAttachedReward(context: modelContext) {
            print("🔥 Burned attached reward for activity '\(activity.name)'")
        }
        
        // Add time to attached task if configured
        if activity.addTimeToAttachedTask(context: modelContext) {
            print("⏱️ Added time to attached task for activity '\(activity.name)'")
        }
        
        // Find the current window
        for scheduledTime in activity.scheduledTimes {
            let components = calendar.dateComponents([.hour, .minute], from: scheduledTime)
            if let todayTime = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: today) {
                let windowEnd = todayTime.addingTimeInterval(activity.windowDuration)
                if now >= todayTime && now <= windowEnd {
                    let usage = ActivityUsageHistory(
                        activityName: activity.name,
                        usedAt: now,
                        windowStartTime: todayTime,
                        windowEndTime: windowEnd,
                        notes: windowNotes.isEmpty ? nil : windowNotes
                    )
                    modelContext.insert(usage)
                    try? modelContext.save()
                    break
                }
            }
        }
    }
}

struct QuickActivityRowView: View {
    let activity: ScheduledActivity
    let currentTime: Date
    let onUseWindow: () -> Void
    let onUseCredits: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.name)
                        .font(.headline)
                    
                    Spacer()
                }
                
                // Make "Next in" more dominant and put it first
                if activity.isInActiveWindow() {
                    if let windowEnd = activity.currentWindowEndTime() {
                        let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                        Text("Window closes in \(timeString(from: remaining))")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                } else if let nextTime = activity.nextScheduledTime() {
                    let timeUntilNext = nextTime.timeIntervalSince(currentTime)
                    Text("Next in \(timeString(from: timeUntilNext))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
                
                // Put reward and task metrics below "Next in"
                HStack(spacing: 8) {
                    // Show reward count if there are accumulated credits
                    if activity.accumulatedWindowCredits > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "gift.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("\(activity.accumulatedWindowCredits)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    // Show attached reward if configured
                    if activity.hasRewardAttachment {
                        HStack(spacing: 4) {
                            Image(systemName: activity.effectiveRewardBurnType.icon)
                                .font(.caption)
                                .foregroundColor(.purple)
                            Text(activity.formattedBurnAmount())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    // Show attached task if configured
                    if activity.hasTaskAttachment {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.badge.plus.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(activity.formattedTaskTime())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if activity.isInActiveWindow() {
                    Button {
                        onUseWindow()
                    } label: {
                        Text("Use")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
                
                if activity.accumulatedWindowCredits > 0 {
                    Button {
                        onUseCredits()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gift.fill")
                                .font(.caption)
                            Text("Use")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .cornerRadius(8)
                    }
                }
                
                if !activity.isInActiveWindow() && activity.accumulatedWindowCredits == 0 {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

struct CreditUseView: View {
    @Environment(\.modelContext) private var modelContext
    let activity: ScheduledActivity
    @Binding var creditsToUse: Int
    let onUse: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Use Window Credits")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(activity.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 12) {
                    Text("Available Credits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "gift.fill")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("\(activity.accumulatedWindowCredits)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                
                VStack(spacing: 12) {
                    Text("Credits to Use")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        Button {
                            if creditsToUse > 1 {
                                creditsToUse -= 1
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title)
                                .foregroundColor(creditsToUse > 1 ? .blue : .gray)
                        }
                        .disabled(creditsToUse <= 1)
                        
                        Text("\(creditsToUse)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .frame(minWidth: 60)
                        
                        Button {
                            if creditsToUse < activity.accumulatedWindowCredits {
                                creditsToUse += 1
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundColor(creditsToUse < activity.accumulatedWindowCredits ? .blue : .gray)
                        }
                        .disabled(creditsToUse >= activity.accumulatedWindowCredits)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Show what will happen
                VStack(alignment: .leading, spacing: 8) {
                    if activity.hasRewardAttachment {
                        HStack(spacing: 8) {
                            Image(systemName: activity.effectiveRewardBurnType.icon)
                                .foregroundColor(.purple)
                            Text("Will burn: \(activity.formattedBurnAmount(multiplier: creditsToUse))")
                                .font(.subheadline)
                        }
                    }
                    
                    if activity.hasTaskAttachment {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.badge.plus.fill")
                                .foregroundColor(.blue)
                            Text("Will add: \(activity.formattedTaskTime(multiplier: creditsToUse))")
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
                        onUse()
                    } label: {
                        Text("Use Credits")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        if activity.ignoreWindowCredits(creditsToUse, context: modelContext) {
                            try? modelContext.save()
                        }
                        onCancel()
                    } label: {
                        Text("Ignore Credits")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    Button {
                        onCancel()
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
    QuickActivityButton()
        .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self, Reward.self, Task.self], inMemory: true)
}