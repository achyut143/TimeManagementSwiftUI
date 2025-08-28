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
    
    func scheduleRepeatingIntervalNotifications(intervalMinutes: Int, intervalSeconds: Int = 0, currentCounter: Int = 0) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["repeating-interval"])
        
        let totalSeconds = intervalMinutes * 60 + intervalSeconds
        
        // iOS requires at least 60 seconds for repeating notifications
        // For shorter intervals, we'll rely on the timer and one-time notifications
        guard totalSeconds >= 60 else {
            print("⚠️ Interval too short for repeating notifications, using one-time notifications instead")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Focus Alert"
        content.body = "Interval \(currentCounter + 1) - Time for your next interval!"
        content.sound = UNNotificationSound.default
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(totalSeconds),
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
    
    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
    
    func cancelAllIntervalNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let intervalIdentifiers = requests.compactMap { request in
                request.identifier.hasPrefix("interval-") || request.identifier.hasPrefix("alert-") ? request.identifier : nil
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: intervalIdentifiers)
        }
    }
    
    // Enhanced notification for real devices with free developer accounts
    func scheduleEnhancedIntervalNotification(counter: Int, intervalName: String, timeInterval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Focus Alert - Interval \(counter)"
        content.body = intervalName
        content.sound = UNNotificationSound.default
        content.badge = NSNumber(value: counter)
        
        // Add custom data for better tracking
        content.userInfo = [
            "interval": counter,
            "timestamp": Date().timeIntervalSince1970,
            "type": "focus_interval"
        ]
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: "enhanced-interval-\(counter)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to schedule enhanced notification: \(error.localizedDescription)")
            } else {
                print("✅ Scheduled enhanced notification for interval \(counter)")
            }
        }
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
            // User tapped on notification - the timer in AlertSettings already handles the counter increment
            // No need to post notification here as it would be duplicate
            print("📱 User tapped interval notification - timer already handled it")
        }
        
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        // The timer in AlertSettings already handles the counter increment and notification posting
        // This just controls the visual presentation of the notification
        if notification.request.identifier == "repeating-interval" {
            print("📱 Showing interval notification in foreground - timer already handled it")
        }
        
        completionHandler([.banner, .sound, .badge])
    }
}