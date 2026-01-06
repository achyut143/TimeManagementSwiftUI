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
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive }, sort: \ScheduledActivity.createdAt, order: .reverse)
    private var activities: [ScheduledActivity]
    
    @State private var currentTime = Date()
    @State private var selectedActivity: ScheduledActivity?
    @State private var showActivityWindow = false
    @State private var windowNotes = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(activities, id: \.name) { activity in
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
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
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
                Text(activity.name)
                    .font(.headline)
                
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
        .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self], inMemory: true)
}