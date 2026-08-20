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
            // Any project timer left running when the app is backgrounded or
            // killed gets paused here, so its elapsed time never silently
            // includes time the app wasn't actually running.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                pauseRunningProjectTimers()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                pauseRunningProjectTimers()
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
            Goal.self, DayBlock.self, Project.self, ProjectActivity.self, ProjectTimeEntry.self,
            ProjectTimer.self
        ]
        // Restraints live in a separate store so schema changes never touch existing data.
        let restraintTypes: [any PersistentModel.Type] = [Restraint.self, RestraintInstance.self]
        let mainConfig = ModelConfiguration(schema: Schema(mainTypes))
        let restraintConfig = ModelConfiguration("restraints", schema: Schema(restraintTypes))
        let fullSchema = Schema(mainTypes + restraintTypes)

        do {
            return try ModelContainer(for: fullSchema, configurations: [mainConfig, restraintConfig])
        } catch {
            print("⚠️ Combined ModelContainer init failed: \(error)")

            // Don't guess which store broke — test them independently before
            // touching any files on disk. Blindly wiping "the restraint store"
            // on any failure (the old behavior here) would just as easily nuke
            // restraint data over a problem that was actually in the main store,
            // or over a transient failure that wasn't either store's fault.
            let restraintFailure: Error? = {
                do { _ = try ModelContainer(for: Schema(restraintTypes), configurations: [restraintConfig]); return nil }
                catch { return error }
            }()
            let mainFailure: Error? = {
                do { _ = try ModelContainer(for: Schema(mainTypes), configurations: [mainConfig]); return nil }
                catch { return error }
            }()

            if let restraintFailure {
                print("⚠️ Restraint store fails independently: \(restraintFailure). Backing up (not deleting) and resetting just that store.")
                backUpStoreFiles(at: restraintConfig.url)
            }
            if let mainFailure {
                // No safe automatic recovery for the main store — that risks
                // losing tasks/projects/everything else. Surface it loudly
                // instead of guessing, and do NOT touch its files.
                print("🛑 Main store fails independently of restraints: \(mainFailure). Leaving its files untouched.")
            }

            // Retry now that we've only touched a store we actually confirmed was broken (if any).
            if let recovered = try? ModelContainer(for: fullSchema, configurations: [mainConfig, restraintConfig]) {
                return recovered
            }

            // Still failing and it wasn't cleanly isolated to restraints: fall
            // back to in-memory so the app can launch, rather than deleting
            // anything further. On-disk data is left exactly as it was for a
            // future fix, instead of being silently destroyed.
            print("🛑 Still failing after isolation — falling back to an in-memory store. On-disk data was left untouched.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            return try! ModelContainer(for: fullSchema, configurations: [fallback])
        }
    }

    // Renames (not deletes) a store's files so a broken store never destroys
    // data outright — the corrupt files stay on disk under a "-corrupt-<date>"
    // suffix, out of SwiftData's way, in case they're ever worth recovering.
    private static func backUpStoreFiles(at url: URL) {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for candidate in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            guard fm.fileExists(atPath: candidate.path) else { continue }
            let backupURL = candidate.deletingLastPathComponent()
                .appendingPathComponent(candidate.lastPathComponent + ".corrupt-\(stamp)")
            try? fm.moveItem(at: candidate, to: backupURL)
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