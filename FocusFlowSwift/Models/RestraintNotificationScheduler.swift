import Foundation
import UserNotifications

// Schedules a repeating local notification for each active restraint's
// release window(s), so you get pinged when a window opens instead of
// having to check the app. Re-run this any time restraints are created,
// edited, or deleted — it always clears every "restraint-window-*" request
// first, so it's safe to call repeatedly with the current full list.
enum RestraintNotificationScheduler {
    private static let prefix = "restraint-window-"

    static func rescheduleAll(from restraints: [Restraint]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let toRemove = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: toRemove)

            for restraint in restraints where restraint.isActive && !restraint.isAbstinence {
                for (windowIndex, window) in restraint.timeWindows.enumerated() {
                    schedule(restraint: restraint, window: window, windowIndex: windowIndex, center: center)
                }
            }
        }
    }

    private static func schedule(restraint: Restraint, window: RestraintTimeWindowInfo, windowIndex: Int, center: UNUserNotificationCenter) {
        // weekday nil = every day (one daily trigger); otherwise one trigger per scheduled weekday.
        let weekdaysToSchedule: [Int?] = restraint.weekdays.isEmpty ? [nil] : restraint.weekdays.map { $0 }

        let amount = restraint.effectiveLimitType == .duration
            ? "\(Int(restraint.effectiveAward(for: window))) min"
            : formattedQuantity(restraint.effectiveAward(for: window), unit: restraint.quantityUnit)

        for weekday in weekdaysToSchedule {
            var comps = DateComponents()
            comps.hour = window.hour
            comps.minute = window.minute
            if let weekday { comps.weekday = weekday }

            let content = UNMutableNotificationContent()
            content.title = "\(restraint.name) is open"
            content.body = "Release window is open — \(amount) awarded. Log it when you're done."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let identifier = "\(prefix)\(restraint.id.uuidString)-\(windowIndex)-\(weekday.map(String.init) ?? "any")"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private static func formattedQuantity(_ value: Double, unit: String) -> String {
        let num = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        return "\(num) \(unit)"
    }
}
