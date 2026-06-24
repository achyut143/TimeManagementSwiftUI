import SwiftUI
import SwiftData

struct QuickActivityButton: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isTaskFormPresented) private var isTaskFormPresented
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive }, sort: \ScheduledActivity.createdAt, order: .reverse)
    private var activities: [ScheduledActivity]
    
    @State private var showActivitiesList = false
    @State private var currentTime = Date()
    @State private var refreshTrigger = UUID()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var hasActiveWindow: Bool {
        return activities.contains { $0.isInActiveWindow() }
    }
    
    var totalDailyCredits: Int {
        return activities
            .filter { ($0.recurrenceType ?? .daily) == .daily }
            .reduce(0) { $0 + $1.accumulatedWindowCredits }
    }

    var totalPeriodCredits: Int {
        return activities
            .filter {
                let type = $0.recurrenceType ?? .daily
                return type == .weekly || type == .monthly || type == .quarterly
            }
            .reduce(0) { $0 + $1.accumulatedWindowCredits }
    }

    @ViewBuilder
    private func creditBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .frame(minWidth: 18, minHeight: 18)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(spacing: 12) {
                    if !activities.isEmpty {
                        Button {
                            showActivitiesList = true
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(hasActiveWindow ? Color.green : Color.blue)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                                VStack(spacing: 2) {
                                    Image(systemName: hasActiveWindow ? "clock.badge.checkmark.fill" : "clock.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)

                                    if !hasActiveWindow {
                                        Text("Low level")
                                            .font(.system(size: 6, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }

                                // Daily credits badge — orange, top-right
                                if totalDailyCredits > 0 {
                                    creditBadge(totalDailyCredits, color: .orange)
                                        .offset(x: 22, y: -22)
                                }

                                // Period credits badge (weekly/monthly/quarterly) — purple, top-left
                                if totalPeriodCredits > 0 {
                                    creditBadge(totalPeriodCredits, color: .purple)
                                        .offset(x: -22, y: -22)
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
            QuickActivitiesListView(activities: activities, refreshTrigger: refreshTrigger)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivityUpdated"))) { _ in
            // Refresh when activities are updated
            refreshTrigger = UUID()
        }
    }
}

struct QuickActivitiesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Query directly instead of using passed activities
    @Query(filter: #Predicate<ScheduledActivity> { $0.isActive }, sort: \ScheduledActivity.createdAt, order: .reverse)
    private var activities: [ScheduledActivity]
    
    @AppStorage("quickActivities_groupByRecurrence") private var groupByRecurrence = false

    @State private var currentTime = Date()
    @State private var selectedActivity: ScheduledActivity?
    @State private var showActivityWindow = false
    @State private var showCreditUseSheet = false
    @State private var windowNotes = ""
    @State private var creditsToUse = 1
    @State private var refreshTrigger: UUID
    @State private var forceRefresh = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    init(activities: [ScheduledActivity], refreshTrigger: UUID) {
        // We ignore the passed activities and query directly
        _refreshTrigger = State(initialValue: refreshTrigger)
    }
    
    var sortedActivities: [ScheduledActivity] {
        _ = forceRefresh
        return activities.sorted { sortPriority(for: $0) < sortPriority(for: $1) }
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
    
    var body: some View {
        NavigationStack {
            List {
                if groupByRecurrence {
                    // Grouped by recurrence type
                    if !dailyActivities.isEmpty {
                        Section(header: HStack {
                            Image(systemName: "calendar").foregroundColor(.blue)
                            Text("Daily").font(.headline)
                        }) {
                            ForEach(dailyActivities, id: \.name) { activity in
                                rowView(for: activity)
                            }
                        }
                    }
                    if !weeklyActivities.isEmpty {
                        Section(header: HStack {
                            Image(systemName: "calendar.badge.clock").foregroundColor(.green)
                            Text("Weekly").font(.headline)
                        }) {
                            ForEach(weeklyActivities, id: \.name) { activity in
                                rowView(for: activity)
                            }
                        }
                    }
                    if !monthlyActivities.isEmpty {
                        Section(header: HStack {
                            Image(systemName: "calendar.circle").foregroundColor(.orange)
                            Text("Monthly").font(.headline)
                        }) {
                            ForEach(monthlyActivities, id: \.name) { activity in
                                rowView(for: activity)
                            }
                        }
                    }
                    if !quarterlyActivities.isEmpty {
                        Section(header: HStack {
                            Image(systemName: "calendar.badge.plus").foregroundColor(.purple)
                            Text("Quarterly").font(.headline)
                        }) {
                            ForEach(quarterlyActivities, id: \.name) { activity in
                                rowView(for: activity)
                            }
                        }
                    }
                } else {
                    // Flat sorted list
                    ForEach(sortedActivities, id: \.name) { activity in
                        rowView(for: activity)
                    }
                }
            }
            .id(refreshTrigger)
            .navigationTitle("Quick Activities")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        modelContext.processPendingChanges()
                        refreshTrigger = UUID()
                        forceRefresh.toggle()
                        currentTime = Date()
                    } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Toggle(isOn: $groupByRecurrence) {
                        Text("Group")
                            .font(.caption)
                    }
                    .toggleStyle(.button)
                    .tint(.blue)
                    .font(.caption)
                    .controlSize(.mini)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
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
            // Process pending changes to pick up database updates
            modelContext.processPendingChanges()
            forceRefresh.toggle()
        }
        .onAppear {
            // Refresh data when view appears
            modelContext.processPendingChanges()
            forceRefresh.toggle()
        }
    }
    
    @ViewBuilder
    private func rowView(for activity: ScheduledActivity) -> some View {
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

    private func recordActivityUsage(activity: ScheduledActivity) {
        print("🚀 DEBUG: recordActivityUsage called for activity: '\(activity.name)'")
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

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
        HStack(spacing: 12) {
            // Left side: Button and activity info
            VStack(alignment: .leading, spacing: 8) {
                Text(activity.name)
                    .font(.headline)
                
                // Button moved to left side
                Button {
                    onUseCredits()
                } label: {
                    HStack(spacing: 4) {
                        if activity.isInActiveWindow() {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                            Text("Use Window")
                                .font(.caption)
                                .fontWeight(.semibold)
                        } else if activity.accumulatedWindowCredits > 0 {
                            Image(systemName: "gift.fill")
                                .font(.caption)
                            Text("Use Credits")
                                .font(.caption)
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                            Text("Use Overdraft")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        activity.isInActiveWindow() ? Color.green :
                        activity.accumulatedWindowCredits > 0 ? Color.orange :
                        Color.red
                    )
                    .cornerRadius(8)
                }
                
                // Activity metrics
                HStack(spacing: 8) {
                    // Points progress toward next credit
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text(activity.pointsProgressDescription)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)

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

                    if activity.timePerCredit > 0 && activity.accumulatedWindowCredits > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("\(activity.accumulatedWindowCredits) cr = \(Int(activity.timePerCredit * Double(activity.accumulatedWindowCredits)))min")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                    }

                    if activity.hasTaskAttachment {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.badge.plus.fill")
                                .font(.caption)
                                .foregroundColor(.teal)
                            Text(activity.formattedTaskTime())
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.teal)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.teal.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // Right side: Large prominent timer
            if activity.isInActiveWindow() {
                if let windowEnd = activity.currentWindowEndTime() {
                    let remaining = max(0, windowEnd.timeIntervalSince(currentTime))
                    VStack(spacing: 4) {
                        Text(timeString(from: remaining))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.red)
                            .monospacedDigit()
                        
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text("left")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                }
            } else if let nextTime = activity.nextScheduledTime() {
                let timeUntilNext = nextTime.timeIntervalSince(currentTime)
                VStack(spacing: 4) {
                    Text(timeString(from: timeUntilNext))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundColor(.blue)
                        .monospacedDigit()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("next")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func timeString(from interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        } else {
            return "\(minutes):\(String(format: "%02d", seconds))"
        }
    }
}

struct CreditUseView: View {
    @Environment(\.modelContext) private var modelContext
    let activity: ScheduledActivity
    @Binding var creditsToUse: Int
    let onUse: () -> Void
    let onCancel: () -> Void
    
    @State private var showTimerConfirmation = false
    @State private var pendingTimerMinutes: Double = 0
    @State private var pendingAction: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Use Activity Window")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(activity.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                // Show active window option if in window
                if activity.isInActiveWindow() {
                    VStack(spacing: 12) {
                        Text("Active Window")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button {
                            // Use the regular window
                            // This will be handled by the parent
                            onUse()
                        } label: {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                Text("Use Current Window")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        
                        if let windowEnd = activity.currentWindowEndTime() {
                            let remaining = max(0, windowEnd.timeIntervalSince(Date()))
                            Text("Window closes in \(timeString(from: remaining))")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                    
                    Divider()
                }
                
                // Show credits section if available
                if activity.accumulatedWindowCredits > 0 {
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
                        if activity.hasTaskAttachment {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.badge.plus.fill")
                                    .foregroundColor(.teal)
                                Text("Will add: \(activity.formattedTaskTime(multiplier: creditsToUse))")
                                    .font(.subheadline)
                            }
                        }

                        if activity.timePerCredit > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.blue)
                                Text("Activity time: \(Int(activity.timePerCredit * Double(creditsToUse))) min")
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Overdraft Section — borrow 1 credit (creates debt repaid by future tasks)
                VStack(spacing: 12) {
                    let canBorrow = activity.canOverdraft
                    Button {
                        handleOverdraftUse()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Borrow 1 Credit")
                                    .fontWeight(.semibold)
                                if activity.overdraftDebt > 0 {
                                    Text("Debt: \(String(format: "%.1f", activity.overdraftDebt)) pts")
                                        .font(.caption)
                                        .opacity(0.85)
                                } else {
                                    Text("Repaid by future task points")
                                        .font(.caption)
                                        .opacity(0.85)
                                }
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(canBorrow ? Color.red : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canBorrow)
                }
                
                Spacer()
                
                if activity.accumulatedWindowCredits > 0 && !activity.isInActiveWindow() {
                    VStack(spacing: 12) {
                        Button {
                            handleCreditUse()
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
                                .background(Color.gray)
                                .cornerRadius(12)
                        }
                    }
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
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Start Timer?", isPresented: $showTimerConfirmation) {
            Button("Yes, Start Timer") {
                if #available(iOS 16.1, *) {
                    ActivityTimerManager.shared.startTimer(
                        activityName: activity.name,
                        durationMinutes: pendingTimerMinutes
                    )
                }
                pendingAction?()
            }
            Button("No, Just Use") {
                pendingAction?()
            }
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text("Would you like to start a \(Int(pendingTimerMinutes)) minute timer in the Dynamic Island?")
        }
    }
    
    private func handleCreditUse() {
        // Calculate timer duration based on timePerCredit and/or task attachment
        var timerMinutes: Double = 0

        // Add time-per-credit if configured
        if activity.timePerCredit > 0 {
            timerMinutes += activity.timePerCredit * Double(creditsToUse)
        }

        // Add task time if available
        if activity.hasTaskAttachment {
            timerMinutes += activity.taskTimeAmount * Double(creditsToUse)
        }

        // Show timer confirmation if there's any time to track
        if timerMinutes > 0 {
            pendingTimerMinutes = timerMinutes
            pendingAction = {
                onUse()
            }
            showTimerConfirmation = true
        } else {
            // No time attachments, just use credits
            onUse()
        }
    }
    
    private func handleOverdraftUse() {
        if activity.useOverdraftCredit(context: modelContext) {
            try? modelContext.save()
        }
        onCancel()
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

// MARK: - Environment Key for Task Form Presentation
private struct IsTaskFormPresentedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isTaskFormPresented: Bool {
        get { self[IsTaskFormPresentedKey.self] }
        set { self[IsTaskFormPresentedKey.self] = newValue }
    }
}

#Preview {
    QuickActivityButton()
        .modelContainer(for: [ScheduledActivity.self, ActivityUsageHistory.self, Task.self], inMemory: true)
}