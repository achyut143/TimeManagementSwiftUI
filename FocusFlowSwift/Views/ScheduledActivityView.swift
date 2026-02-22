import SwiftUI
import SwiftData

struct ScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var activities: [ScheduledActivity]
    @Query private var usageHistory: [ActivityUsageHistory]
    
    @State private var showNewActivitySheet = false
    @State private var showHistorySheet = false
    @State private var showRewardsSheet = false
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
        let filtered = activities.filter { $0.isActive }
        return filtered.sorted { activity1, activity2 in
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
                HStack {
                    Button {
                        showHistorySheet = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    
                    Button {
                        showRewardsSheet = true
                    } label: {
                        Image(systemName: "gift.fill")
                            .foregroundColor(.orange)
                    }
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
        .sheet(isPresented: $showRewardsSheet) {
            ActivityRewardsView()
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
            checkForExpiredWindows()
        }
        .onAppear {
            checkForExpiredWindows()
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
        print("🚀 DEBUG: recordActivityUsage called for activity: '\(activity.name)'")
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Mark window as used for reward tracking
        activity.markWindowAsUsed()
        
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
    
    private func deleteActivity(_ activity: ScheduledActivity) {
        modelContext.delete(activity)
        try? modelContext.save()
    }
    
    private func checkForExpiredWindows() {
        for activity in activeActivities {
            // Check and reset counters first
            activity.checkAndResetCounters()
            
            // Get windows that have passed unused in the current period
            let passedWindows = activity.getPassedUnusedWindows()
            
            // For recently edited activities, be more conservative about bulk marking
            let expectedSkipped = passedWindows.count
            
            if activity.windowsSkippedInPeriod < expectedSkipped {
                // Calculate how many new windows to mark as skipped
                let newlySkipped = expectedSkipped - activity.windowsSkippedInPeriod
                
                // For recently edited activities, only mark 1 window at a time to prevent bulk marking
                // For normal activities, allow up to 3 windows per cycle
                let maxWindowsToSkip = activity.needsPostEditReset() ? 1 : min(newlySkipped, 3)
                let windowsToSkip = min(newlySkipped, maxWindowsToSkip)
                
                if windowsToSkip > 0 {
                    print("🔍 Activity '\(activity.name)': Found \(newlySkipped) newly passed windows, marking \(windowsToSkip) as skipped (recently edited: \(activity.needsPostEditReset()))")
                    
                    for _ in 0..<windowsToSkip {
                        activity.markWindowAsSkipped()
                    }
                    try? modelContext.save()
                }
            }
        }
    }
}

struct ActivityCardView: View {
    let activity: ScheduledActivity
    let currentTime: Date
    let onUseWindow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var showChart = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Image(systemName: activity.effectiveRecurrenceType.icon)
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(activity.effectiveRecurrenceType.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
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
            
            // Recurrence Days Display
            if activity.effectiveRecurrenceType != .daily {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recurrence Days:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("(\(activity.effectiveRecurrenceType.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    let days = getRecurrenceDaysDisplay(for: activity)
                    if !days.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                            ForEach(days, id: \.self) { dayText in
                                Text(dayText)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                    } else {
                        Text("No days selected")
                            .font(.caption)
                            .foregroundColor(.red)
                            .italic()
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
            
            // Window Credits Display
            if activity.accumulatedWindowCredits > 0 {
                HStack {
                    Text("Window Credits:")
                    Spacer()
                    Text(activity.formattedWindowCredits())
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Overdraft Display
            if activity.overdraftWindowsUsed > 0 {
                HStack {
                    Text("Overdraft Used:")
                    Spacer()
                    Text("\(activity.overdraftWindowsUsed) \(activity.overdraftWindowsUsed == 1 ? "window" : "windows")")
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                .font(.subheadline)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Chart Button
            Button {
                showChart = true
            } label: {
                HStack {
                    Image(systemName: "chart.bar.fill")
                    Text("View Usage Chart")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
            }
            
            // Attached Reward Display
            if activity.hasRewardAttachment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Attached Reward:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let reward = activity.getAttachedReward(context: modelContext) {
                            HStack(spacing: 4) {
                                Image(systemName: reward.type.icon)
                                    .font(.caption)
                                Text(reward.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.purple)
                        }
                    }
                    
                    HStack {
                        Text("Burns:")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: activity.effectiveRewardBurnType.icon)
                                .font(.caption)
                            Text(activity.formattedBurnAmount())
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.red)
                    }
                    .font(.caption)
                    
                    // Show if reward can afford the burn
                    if let reward = activity.getAttachedReward(context: modelContext) {
                        HStack {
                            Text("Available:")
                            Spacer()
                            Text(reward.formattedAmount())
                                .foregroundColor(activity.canBurnReward(context: modelContext) ? .green : .red)
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Attached Task Display
            if activity.hasTaskAttachment {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Attached Task:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let task = activity.getAttachedTask(context: modelContext) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                Text(task.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("Adds:")
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "clock.badge.plus.fill")
                                .font(.caption)
                            Text(activity.formattedTaskTime())
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.green)
                    }
                    .font(.caption)
                    
                    // Show current task progress
                    if let task = activity.getAttachedTask(context: modelContext) {
                        HStack {
                            Text("Current:")
                            Spacer()
                            let currentTime = task.timeSpent ?? 0.0
                            let allocatedTime = task.allocatedTimeInMinutes
                            if allocatedTime > 0 {
                                let percentage = min(currentTime / allocatedTime, 1.0) * 100
                                Text("\(Int(percentage))% (\(formatTaskTime(currentTime)))")
                                    .foregroundColor(percentage >= 100 ? .green : .orange)
                            } else {
                                Text(formatTaskTime(currentTime))
                                    .foregroundColor(.blue)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
            
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
                        
                        // Use Window Credit Button
                        if activity.accumulatedWindowCredits >= 1 {
                            Button {
                                if activity.useWindowCredits(1, context: modelContext) {
                                    try? modelContext.save()
                                }
                            } label: {
                                Label("Use 1 Window Credit", systemImage: "gift.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            } else if let nextTime = activity.nextScheduledTime() {
                let timeUntilNext = nextTime.timeIntervalSince(currentTime)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Next window in:")
                        Spacer()
                        Text(timeString(from: timeUntilNext))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                    
                    // Use Window Credit Button (when not in active window)
                    if activity.accumulatedWindowCredits >= 1 {
                        Button {
                            if activity.useWindowCredits(1, context: modelContext) {
                                try? modelContext.save()
                            }
                        } label: {
                            Label("Use 1 Window Credit", systemImage: "gift.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
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
    
    private func formatTaskTime(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let mins = Int(minutes) % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(Int(minutes)) min"
        }
    }
    
    private func getRecurrenceDaysDisplay(for activity: ScheduledActivity) -> [String] {
        print("📅 Getting recurrence days for '\(activity.name)' - Type: \(activity.effectiveRecurrenceType.displayName)")
        print("📅 Weekdays: \(activity.selectedWeekdays), Month days: \(activity.selectedMonthDays), Months: \(activity.selectedMonths)")
        
        switch activity.effectiveRecurrenceType {
        case .daily:
            return [] // Daily activities don't need day display
            
        case .weekly:
            let result = activity.selectedWeekdays.sorted().map { weekday in
                Calendar.current.weekdaySymbols[weekday - 1]
            }
            print("📅 Weekly display: \(result)")
            return result
            
        case .monthly:
            let result = activity.selectedMonthDays.sorted().map { day in
                "\(day)"
            }
            print("📅 Monthly display: \(result)")
            return result
            
        case .quarterly:
            var result: [String] = []
            
            // Add selected months
            let months = activity.selectedMonths.sorted().map { month in
                Calendar.current.monthSymbols[month - 1]
            }
            result.append(contentsOf: months)
            
            // Add selected days with "Day" prefix to distinguish from months
            let days = activity.selectedMonthDays.sorted().map { day in
                "Day \(day)"
            }
            result.append(contentsOf: days)
            
            print("📅 Quarterly display: \(result)")
            return result
        }
    }
}

#Preview {
    NavigationStack {
        ScheduledActivityView()
    }
    .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self, Reward.self, Task.self], inMemory: true)
}