import SwiftUI
import SwiftData
import BackgroundTasks
import AVFoundation
import UserNotifications

@main
struct FocusFlowSwiftApp: App {
    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.focusflow.refresh", using: nil) { task in
            Self.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
        
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        NotificationManager.shared.requestPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    Self.scheduleBackgroundTask()
                }
        }
        .modelContainer(for: [AlertSettings.self, Task.self, Habit.self])
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
