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
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
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
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .environmentObject(alertManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        alertManager.handleAppLifecycleChange(isActive: false)
                        Self.scheduleBackgroundTask()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        alertManager.handleAppLifecycleChange(isActive: true)
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                        NotificationCenter.default.post(name: NSNotification.Name("CheckExpiredWindows"), object: nil)
                    }
            }
        }
        .modelContainer(Self.makeContainer())
    }

    private static func makeContainer() -> ModelContainer {
        let mainTypes: [any PersistentModel.Type] = [
            Task.self, Subtask.self, Habit.self, CycleConfiguration.self, CyclePhase.self,
            AlertInstance.self, ScheduledActivity.self, ActivityUsageHistory.self, DailyNote.self,
            HabitSettings.self, TaskAttachment.self, ArchivedHabit.self, EventDay.self,
            Book.self, BookQuote.self, ScheduleTemplate.self, TaskOKR.self, TaskInsight.self,
            Goal.self, DayBlock.self
        ]
        // Restraints live in a separate store so schema changes never touch existing data.
        let mainConfig = ModelConfiguration(schema: Schema(mainTypes))
        let restraintConfig = ModelConfiguration("restraints", schema: Schema([Restraint.self, RestraintInstance.self]))
        let fullSchema = Schema(mainTypes + [Restraint.self, RestraintInstance.self])
        do {
            return try ModelContainer(for: fullSchema, configurations: [mainConfig, restraintConfig])
        } catch {
            // Only the restraint store can cause a migration failure; wipe it and retry.
            let url = restraintConfig.url
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: url.appendingPathExtension("shm"))
            return try! ModelContainer(for: fullSchema, configurations: [mainConfig, restraintConfig])
        }
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