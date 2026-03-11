import SwiftUI
import SwiftData
import BackgroundTasks
import AVFoundation
import UserNotifications
import ActivityKit
import WidgetKit

// Wrapper view to handle migration with access to modelContext
struct MigrationWrapper<Content: View>: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hasMigrated = false
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .onAppear {
                if !hasMigrated {
                    TaskAttachmentMigration.migrateAttachmentsIfNeeded(modelContext: modelContext)
                    hasMigrated = true
                }
            }
    }
}

@main
struct FocusFlowSwiftApp: App {
    @StateObject private var alertManager = AlertManager()
    @StateObject private var backgroundCounter = BackgroundCounterManager.shared
    
    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.focusflow.refresh", using: nil) { task in
            Self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        NotificationManager.shared.requestPermission()
        NotificationManager.shared.setupNotificationDelegate()
    }
    
    var body: some Scene {
        WindowGroup {
            MigrationWrapper {
                ContentView()
                    .environmentObject(alertManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        alertManager.handleAppLifecycleChange(isActive: false)
                        backgroundCounter.handleAppDidEnterBackground()
                        Self.scheduleBackgroundTask()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        alertManager.handleAppLifecycleChange(isActive: true)
                        backgroundCounter.handleAppDidBecomeActive()
                        // Clean up any delivered notifications when app becomes active
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                        // Check for expired activity windows and award credits
                        NotificationCenter.default.post(name: NSNotification.Name("CheckExpiredWindows"), object: nil)
                    }
            }
        }
        .modelContainer(for: [Task.self, Subtask.self, Habit.self, CycleConfiguration.self, CyclePhase.self, AlertInstance.self, Reward.self, RewardTransaction.self, ScheduledActivity.self, ActivityUsageHistory.self, DailyNote.self, HabitSettings.self, TaskAttachment.self, ArchivedHabit.self, EventDay.self, Book.self, BookQuote.self])
    }
    
    private static func handleBackgroundRefresh(task: BGAppRefreshTask) {
        scheduleBackgroundTask()
        task.setTaskCompleted(success: true)
    }
    
    private static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.focusflow.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}