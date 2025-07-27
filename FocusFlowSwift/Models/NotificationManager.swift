import UserNotifications
import AVFoundation

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
    }
    
    func scheduleNotification(title: String, body: String, identifier: String, timeInterval: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleTaskStartNotification(task: Task) {
        scheduleNotification(
            title: "Task Starting",
            body: "Time to start: \(task.title)",
            identifier: "task-start-\(task.title)"
        )
    }
    
    func scheduleTaskEndNotification(task: Task) {
        scheduleNotification(
            title: "Task Ending",
            body: "Time to end: \(task.title)",
            identifier: "task-end-\(task.title)"
        )
    }
    
    func scheduleIntervalNotification(counter: Int) {
        scheduleNotification(
            title: "Interval Alert",
            body: "Interval \(counter)",
            identifier: "interval-\(counter)"
        )
    }
    
    func scheduleTaskCompletedNotification(task: Task) {
        scheduleNotification(
            title: "Task Completed",
            body: "Task completed: \(task.title)",
            identifier: "task-completed-\(task.title)"
        )
    }
    
    func scheduleTaskNotCompletedNotification(task: Task) {
        scheduleNotification(
            title: "Task Not Completed",
            body: "Task marked as not completed: \(task.title)",
            identifier: "task-not-completed-\(task.title)"
        )
    }
}