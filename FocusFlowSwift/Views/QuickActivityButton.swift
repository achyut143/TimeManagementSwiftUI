import SwiftUI
import SwiftData

struct QuickActivityButton: View {
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive }, sort: \ScheduledActivity.createdAt, order: .reverse)
    private var activities: [ScheduledActivity]
    
    @State private var showNewActivity = false
    @State private var showActivitiesList = false
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var hasActiveWindow: Bool {
        activities.contains { $0.isInActiveWindow() }
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
                            showActivitiesList = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(hasActiveWindow ? Color.green : Color.blue)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                                
                                Image(systemName: hasActiveWindow ? "clock.badge.checkmark.fill" : "clock.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // New Activity Button
                    Button {
                        showNewActivity = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.purple)
                                .frame(width: 50, height: 50)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 100) // Above tab bar
            }
        }
        .sheet(isPresented: $showNewActivity) {
            NewScheduledActivityView()
        }
        .sheet(isPresented: $showActivitiesList) {
            QuickActivitiesListView()
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
    @State private var windowNotes = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
                ForEach(sortedActivities, id: \.name) { activity in
                    QuickActivityRowView(
                        activity: activity,
                        currentTime: currentTime,
                        onUseWindow: {
                            selectedActivity = activity
                            showActivityWindow = true
                        }
                    )
                }
            }
            .navigationTitle("Quick Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        .onReceive(timer) { _ in
            currentTime = Date()
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activity.name)
                        .font(.headline)
                    
                    Spacer()
                    
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
                }
                
                if activity.isInActiveWindow() {
                    if let windowEnd = activity.currentWindowEndTime() {
                        let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                        Text("Window closes in \(timeString(from: remaining))")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else if let nextTime = activity.nextScheduledTime() {
                    let timeUntilNext = nextTime.timeIntervalSince(currentTime)
                    Text("Next in \(timeString(from: timeUntilNext))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
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
            } else {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
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

#Preview {
    QuickActivityButton()
        .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self, Reward.self, Task.self], inMemory: true)
}