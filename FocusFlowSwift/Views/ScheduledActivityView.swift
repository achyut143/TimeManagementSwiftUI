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
    @State private var searchText = ""

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var activeActivities: [ScheduledActivity] {
        let filtered = activities.filter { activity in
            guard activity.isActive else { return false }
            guard !searchText.isEmpty else { return true }
            return activity.name.localizedCaseInsensitiveContains(searchText) ||
                   activity.effectiveRecurrenceType.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return filtered.sorted { sortPriority(for: $0) < sortPriority(for: $1) }
    }

    // Priority tuple: (group 0-3, tiebreak time)
    // 0 = active window (least time remaining first)
    // 1 = credits available, not in window (soonest next window first)
    // 2 = upcoming window (soonest first)
    // 3 = no upcoming window
    private func sortPriority(for activity: ScheduledActivity) -> (Int, TimeInterval) {
        if activity.isInActiveWindow() {
            let remaining = activity.currentWindowEndTime()?.timeIntervalSince(currentTime) ?? 0
            return (0, remaining)
        } else if activity.accumulatedWindowCredits > 0 {
            let next = activity.nextScheduledTime()?.timeIntervalSince(currentTime) ?? .greatestFiniteMagnitude
            return (1, next)
        } else if let next = activity.nextScheduledTime() {
            return (2, next.timeIntervalSince(currentTime))
        } else {
            return (3, .greatestFiniteMagnitude)
        }
    }
    
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            
            VStack(spacing: 20) {
                if activities.filter({ $0.isActive }).isEmpty {
                    noActivitiesView
                } else if activeActivities.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No results for \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search activities")
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
            // Credit checking now handled by ContentView
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivityUpdated"))) { _ in
            // Refresh when activities are updated from ContentView
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
        print("🚀 DEBUG: recordActivityUsage called for activity: '\(activity.name)'")
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Mark window as used for tracking
        activity.markWindowAsUsed()

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
}

struct ActivityCardView: View {
    let activity: ScheduledActivity
    let currentTime: Date
    let onUseWindow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var showChart = false
    
    var isActive: Bool { activity.isInActiveWindow() }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {

            // Row 1: Name + badges + chart + menu
            HStack(spacing: 6) {
                Image(systemName: activity.effectiveRecurrenceType.icon)
                    .font(.caption2)
                    .foregroundColor(.blue)

                Text(activity.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if isActive {
                    Text("LIVE")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.green).cornerRadius(4)
                }

                if activity.accumulatedWindowCredits > 0 {
                    Label("\(activity.accumulatedWindowCredits)", systemImage: "gift.fill")
                        .font(.caption2).foregroundColor(.orange)
                }

                if activity.overdraftDebt > 0 {
                    Label(String(format: "%.0f", activity.overdraftDebt) + "pt debt", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundColor(.red)
                }

                Button { showChart = true } label: {
                    Image(systemName: "chart.bar")
                        .font(.caption).foregroundColor(.secondary)
                }

                Menu {
                    Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            // Row 2: Time pills + duration
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(activity.scheduledTimes.indices, id: \.self) { i in
                            Text(activity.scheduledTimes[i], style: .time)
                                .font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill)).cornerRadius(4)
                        }
                    }
                }
                HStack(spacing: 2) {
                    Image(systemName: "timer").font(.caption2)
                    Text(durationString(from: activity.windowDuration)).font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            // Row 2.5: Points progress toward next credit
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 5)
                        Capsule()
                            .fill(activity.pointsProgress >= 1.0 ? Color.green : Color.orange)
                            .frame(width: geo.size.width * activity.pointsProgress, height: 5)
                    }
                }
                .frame(height: 5)
                Text(activity.pointsProgressDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize()
            }
            .frame(height: 14)

            // Row 3: Recurrence days (non-daily)
            if activity.effectiveRecurrenceType != .daily {
                let days = getRecurrenceDaysDisplay(for: activity)
                if !days.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(days, id: \.self) { day in
                                Text(day)
                                    .font(.caption2)
                                    .padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue).cornerRadius(3)
                            }
                        }
                    }
                } else {
                    Text("No days selected")
                        .font(.caption2).foregroundColor(.red).italic()
                }
            }

            // Row 4: Attachments (task + time-per-credit inline)
            if activity.hasTaskAttachment || activity.timePerCredit > 0 {
                HStack(spacing: 10) {
                    if activity.hasTaskAttachment,
                       let task = activity.getAttachedTask(context: modelContext) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle").font(.caption2)
                            Text(task.title).font(.caption2).lineLimit(1)
                            Text("+\(activity.formattedTaskTime())").font(.caption2).fontWeight(.medium)
                        }
                        .foregroundColor(.teal)
                    }

                    if activity.timePerCredit > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.caption2)
                            Text("\(Int(activity.timePerCredit)) min/credit").font(.caption2).fontWeight(.medium)
                        }
                        .foregroundColor(.blue)
                    }

                    Spacer(minLength: 0)
                }
            }

            // Row 5: Status + action buttons
            HStack(spacing: 6) {
                if isActive, let windowEnd = activity.currentWindowEndTime() {
                    let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                    HStack(spacing: 3) {
                        Image(systemName: "clock.fill").font(.caption2).foregroundColor(.red)
                        Text(timeString(from: remaining))
                            .font(.caption2.monospacedDigit()).foregroundColor(.red)
                    }

                    Spacer()

                    Button(action: onUseWindow) {
                        Label("Use", systemImage: "play.fill")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.green).foregroundColor(.white).cornerRadius(7)
                    }

                    if activity.accumulatedWindowCredits >= 1 {
                        Button {
                            if activity.useWindowCredits(1, context: modelContext) { try? modelContext.save() }
                        } label: {
                            Label("1cr", systemImage: "gift.fill")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color.orange).foregroundColor(.white).cornerRadius(7)
                        }
                    }

                } else if let nextTime = activity.nextScheduledTime() {
                    let timeUntil = nextTime.timeIntervalSince(currentTime)
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.caption2).foregroundColor(.blue)
                        Text(timeString(from: timeUntil))
                            .font(.caption2.monospacedDigit()).foregroundColor(.blue)
                    }

                    Spacer()

                    if activity.accumulatedWindowCredits >= 1 {
                        Button {
                            if activity.useWindowCredits(1, context: modelContext) { try? modelContext.save() }
                        } label: {
                            Label("1cr", systemImage: "gift.fill")
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color.orange).foregroundColor(.white).cornerRadius(7)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .sheet(isPresented: $showChart) {
            NavigationStack {
                ScrollView { ActivityWindowChartView(activity: activity) }
                    .navigationTitle(activity.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") { showChart = false }
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
                Calendar.current.shortWeekdaySymbols[weekday - 1]
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
    .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self, Task.self], inMemory: true)
}