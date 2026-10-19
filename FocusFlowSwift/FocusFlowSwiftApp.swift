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
                // Settles any away-time exit left pending from a force-quit
                // while the app was backgrounded, up to right now.
                AwayTimeTracker.shared.recordReturn()
                // Starts (or restarts) the continuous in-app focus session.
                FocusSessionTracker.shared.recordEnter()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                AwayTimeTracker.shared.recordReturn()
                FocusSessionTracker.shared.recordEnter()
            }
            // Any project timer left running when the app is backgrounded or
            // killed gets paused here, so its elapsed time never silently
            // includes time the app wasn't actually running.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                pauseRunningProjectTimers()
                AwayTimeTracker.shared.recordExit()
                FocusSessionTracker.shared.recordExit()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                pauseRunningProjectTimers()
                // Safety net — didEnterBackground normally closes the session
                // first, so this is a no-op in the common case.
                FocusSessionTracker.shared.recordExit()
            }
    }

    private func pauseRunningProjectTimers() {
        let descriptor = FetchDescriptor<ProjectTimer>(predicate: #Predicate<ProjectTimer> { $0.runningSince != nil })
        guard let running = try? modelContext.fetch(descriptor), !running.isEmpty else { return }
        for timer in running {
            timer.pause()
        }
        try? modelContext.save()
    }
}

/// One-time cleanup for features removed from the app: cancels their
/// repeating notifications, ends any activity-timer Live Activity, and
/// deletes the separate Rules (restraints) store.
enum RemovedFeaturesCleanup {
    private static let key = "cleanup.removedFeatures.v1"

    static func runOnce() {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("restraint-window-") || $0.hasPrefix("activity-reminder-") }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }

        if #available(iOS 16.1, *) {
            _Concurrency.Task {
                for activity in Activity<ActivityTimerAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        let url = ModelConfiguration("restraints").url
        let fm = FileManager.default
        for file in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] where fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: file)
        }
    }
}

@main
struct FocusFlowSwiftApp: App {
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.focusflow.refresh", using: nil) { task in
            Self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        NotificationManager.shared.requestPermission()
        NotificationManager.shared.setupNotificationDelegate()
        RemovedFeaturesCleanup.runOnce()
    }
    
    var body: some Scene {
        WindowGroup {
            MigrationWrapper {
                ContentView()
                    .preferredColorScheme(isDarkMode ? .dark : .light)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                        Self.scheduleBackgroundTask()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
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
            DailyNote.self,
            HabitSettings.self, TaskAttachment.self, ArchivedHabit.self, EventDay.self,
            Book.self, BookQuote.self, ScheduleTemplate.self, GeneratorTemplate.self, TaskOKR.self, TaskInsight.self,
            Goal.self, DayBlock.self, Project.self, ProjectActivity.self, ProjectTimeEntry.self,
            ProjectTimer.self, BacklogFolder.self, IfThenPlan.self,
            ImpulseType.self, ImpulseBudgetVersion.self, PeriodGoal.self, PlannerDay.self, SleepScheduleVersion.self,
            TabataWorkout.self, RepWorkout.self, WorkoutSession.self, WorkoutPicture.self
        ]
        // Scheduled activities, alerts, the old Plan view and Start with a Why
        // were removed — their tables are dropped by SwiftData's automatic
        // migration. Rules lived in a separate store, deleted by
        // RemovedFeaturesCleanup.
        let mainConfig = ModelConfiguration(schema: Schema(mainTypes))

        do {
            return try ModelContainer(for: Schema(mainTypes), configurations: [mainConfig])
        } catch {
            // No safe automatic recovery for the main store — that risks
            // losing tasks/projects/everything else. Fall back to in-memory so
            // the app can launch, and leave the on-disk files exactly as they
            // were for a future fix.
            print("🛑 ModelContainer init failed: \(error). Falling back to an in-memory store; on-disk data left untouched.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: Schema(mainTypes), configurations: [fallback])
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