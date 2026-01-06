import SwiftUI
import SwiftData

struct ScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [ScheduledActivity]
    @Query private var usageHistory: [ActivityUsageHistory]
    
    @State private var showNewActivitySheet = false
    @State private var showHistorySheet = false
    @State private var currentTime = Date()
    @State private var selectedActivity: ScheduledActivity?
    @State private var showActivityWindow = false
    @State private var windowNotes = ""
    @State private var showEditActivity = false
    @State private var activityToEdit: ScheduledActivity?
    @State private var showDeleteConfirmation = false
    @State private var activityToDelete: ScheduledActivity?
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var activeActivities: [ScheduledActivity] {
        activities.filter { $0.isActive }
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 20) {
                if activeActivities.isEmpty {
                    noActivitiesView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(activeActivities, id: \.name) { activity in
                                ActivityCardView(
                                    activity: activity,
                                    currentTime: currentTime,
                                    onUseWindow: {
                                        selectedActivity = activity
                                        showActivityWindow = true
                                    },
                                    onEdit: {
                                        activityToEdit = activity
                                        showEditActivity = true
                                    },
                                    onDelete: {
                                        activityToDelete = activity
                                        showDeleteConfirmation = true
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                Spacer()
            }
        }
        .navigationTitle("Scheduled Activities")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showHistorySheet = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNewActivitySheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewActivitySheet) {
            NewScheduledActivityView()
        }
        .sheet(isPresented: $showEditActivity) {
            if let activity = activityToEdit {
                EditScheduledActivityView(activity: activity)
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            ActivityHistoryView()
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
        .confirmationDialog(
            "Delete Activity",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let activity = activityToDelete {
                    deleteActivity(activity)
                    activityToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                activityToDelete = nil
            }
        } message: {
            if let activity = activityToDelete {
                Text("Are you sure you want to delete '\(activity.name)'? This action cannot be undone.")
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private var noActivitiesView: some View {
        VStack(spacing: 30) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 80))
                .foregroundColor(.gray)
                .padding(.top, 60)
            
            Text("No Scheduled Activities")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create scheduled activities with time windows to manage your daily routines")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showNewActivitySheet = true
            } label: {
                Label("Create Activity", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: 200)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
            .padding(.top, 20)
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
    
    private func deleteActivity(_ activity: ScheduledActivity) {
        modelContext.delete(activity)
        try? modelContext.save()
    }
}

struct ActivityCardView: View {
    let activity: ScheduledActivity
    let currentTime: Date
    let onUseWindow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text(activity.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                HStack(spacing: 12) {
                    if activity.isInActiveWindow() {
                        Text("ACTIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green)
                            .cornerRadius(6)
                    }
                    
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Scheduled Times
            VStack(alignment: .leading, spacing: 8) {
                Text("Scheduled Times:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach(activity.scheduledTimes.indices, id: \.self) { index in
                        let time = activity.scheduledTimes[index]
                        Text(time, style: .time)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(6)
                    }
                }
            }
            
            // Window Duration
            HStack {
                Text("Window Duration:")
                Spacer()
                Text(durationString(from: activity.windowDuration))
            }
            .font(.subheadline)
            
            // Next Window or Current Status
            if activity.isInActiveWindow() {
                if let windowEnd = activity.currentWindowEndTime() {
                    let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Window closes in:")
                            Spacer()
                            Text(timeString(from: remaining))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                        
                        Button {
                            onUseWindow()
                        } label: {
                            Label("Use Window", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            } else if let nextTime = activity.nextScheduledTime() {
                let timeUntilNext = nextTime.timeIntervalSince(currentTime)
                
                HStack {
                    Text("Next window in:")
                    Spacer()
                    Text(timeString(from: timeUntilNext))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func durationString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    NavigationStack {
        ScheduledActivityView()
    }
    .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self], inMemory: true)
}