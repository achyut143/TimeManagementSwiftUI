import UserNotifications
import AVFoundation

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    private override init() {}
    
    func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }
    
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
    
    //not being used
    func scheduleTaskStartNotification(task: Task) {
        scheduleNotification(
            title: "Task Starting",
            body: "Time to start: \(task.title)",
            identifier: "task-start-\(task.title)"
        )
    }
    
    //   //not being used
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
    
    func scheduleRepeatingIntervalNotifications(intervalMinutes: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["repeating-interval"])
        
        let content = UNMutableNotificationContent()
        content.title = "Focus Alert"
        content.body = "Interval \(AlertSettings.shared.counter + 1) - Time for your next interval!"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(intervalMinutes * 60),
            repeats: true
        )
        
        let request = UNNotificationRequest(
            identifier: "repeating-interval",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    func stopRepeatingNotifications() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["repeating-interval"])
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

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        if response.notification.request.identifier == "repeating-interval" {
            AlertSettings.shared.counter += 1
            
            if let target = AlertSettings.shared.targetIntervals,
               AlertSettings.shared.counter >= target {
                AlertSettings.shared.isPlaying = false
                stopRepeatingNotifications()
            }
        }
        
        completionHandler()
    }
}