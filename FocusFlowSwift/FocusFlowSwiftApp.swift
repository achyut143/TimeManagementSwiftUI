import SwiftUI
import SwiftData
import BackgroundTasks
import AVFoundation
import UserNotifications
import ActivityKit
import WidgetKit

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
                }
        }
        .modelContainer(for: [Task.self, Subtask.self, Habit.self, CycleConfiguration.self, CyclePhase.self, AlertInstance.self, Reward.self, RewardTransaction.self, FastingSession.self, DailyNote.self])
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