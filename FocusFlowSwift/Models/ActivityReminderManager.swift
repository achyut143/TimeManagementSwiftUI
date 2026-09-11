import Foundation
import UserNotifications

/// One shared reminder schedule for the whole Activities list. At each
/// scheduled time it nags with a single fixed message — speech + vibration
/// immediately, then repeating every 8s (via SpeechManager, same as
/// DailyNotesView's "task started" nag) until acknowledged from anywhere —
/// the Activities list, Daily Notes, or Focus View.
class ActivityReminderManager: ObservableObject {
    static let shared = ActivityReminderManager()

    // The one fixed nag message — not tied to any specific activity.
    static let message = "Time to enhance spiritual energy. Please acknowledge."

    private let timesKey = "ActivityReminderManager.times"
    private let enabledKey = "ActivityReminderManager.isEnabled"
    private let acknowledgedKey = "ActivityReminderManager.acknowledgedOccurrences"

    @Published var isPendingAcknowledgment: Bool = false

    private var pendingOccurrenceKey: String?
    private var nagTimer: Timer?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var times: [ActivityReminderTime] {
        get {
            guard let data = UserDefaults.standard.data(forKey: timesKey),
                  let decoded = try? JSONDecoder().decode([ActivityReminderTime].self, from: data) else { return [] }
            return decoded
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            UserDefaults.standard.set(data, forKey: timesKey)
        }
    }

    // MARK: - Acknowledged-occurrence bookkeeping

    private var acknowledgedOccurrences: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: acknowledgedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: acknowledgedKey) }
    }

    private func occurrenceKey(for time: ActivityReminderTime, on date: Date) -> String {
        "\(dateFormatter.string(from: date))|\(time.hour):\(time.minute)"
    }

    // MARK: - Due-reminder check

    // How close to a scheduled time "now" has to be for it to actually ring.
    // Without this, any time that has already passed today counts as "due"
    // forever, so opening the app hours later — or acknowledging one overdue
    // reminder — immediately made the next overdue one fire too, producing a
    // rapid-fire chain that had nothing to do with the times you configured.
    private let graceWindowSeconds: TimeInterval = 15 * 60

    /// Call periodically (every ~30s while foregrounded, and on launch/foreground)
    /// with the current activity list. Only a time that occurred within the last
    /// `graceWindowSeconds` and hasn't been acknowledged yet will actually nag;
    /// anything older than that is considered missed and is silently marked
    /// acknowledged so it doesn't linger or chain into a backlog.
    func check(activities: [VirtueActivity]) {
        guard isEnabled, !times.isEmpty, !activities.isEmpty else { return }
        guard !isPendingAcknowledgment else { return } // already nagging about one occurrence at a time

        let now = Date()
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var acknowledged = acknowledgedOccurrences
        var didSkipAny = false

        // Earliest-first so, within the grace window, a missed morning
        // reminder surfaces before a later one.
        let candidates = times.compactMap { time -> (ActivityReminderTime, Date)? in
            var comps = cal.dateComponents([.year, .month, .day], from: today)
            comps.hour = time.hour
            comps.minute = time.minute
            guard let occurrenceDate = cal.date(from: comps), occurrenceDate <= now else { return nil }
            guard !acknowledged.contains(occurrenceKey(for: time, on: today)) else { return nil }
            return (time, occurrenceDate)
        }.sorted { $0.1 < $1.1 }

        var due: ActivityReminderTime?
        for (time, occurrenceDate) in candidates {
            if now.timeIntervalSince(occurrenceDate) <= graceWindowSeconds {
                due = time
                break
            }
            // Too long past — don't nag for a stale time, just mark it done.
            acknowledged.insert(occurrenceKey(for: time, on: today))
            didSkipAny = true
        }
        if didSkipAny {
            acknowledgedOccurrences = acknowledged
        }

        guard let due else { return }

        pendingOccurrenceKey = occurrenceKey(for: due, on: today)
        beginNagLoop()
    }

    private func beginNagLoop() {
        nagTimer?.invalidate()
        isPendingAcknowledgment = true
        SpeechManager.shared.speak(Self.message)
        nagTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self, self.isPendingAcknowledgment else { return }
            SpeechManager.shared.speak(Self.message)
        }
    }

    /// Stops the current nag and marks that occurrence acknowledged, so
    /// `check` won't immediately re-fire it. Callable from anywhere (the
    /// Activities list, Daily Notes, Focus View) — same "any of several
    /// dedicated banners" pattern as the task-started nag.
    func acknowledge() {
        guard isPendingAcknowledgment else { return }
        isPendingAcknowledgment = false
        nagTimer?.invalidate()
        nagTimer = nil
        SpeechManager.shared.stopSpeaking()
        if let key = pendingOccurrenceKey {
            var acknowledged = acknowledgedOccurrences
            acknowledged.insert(key)
            acknowledgedOccurrences = acknowledged
        }
        pendingOccurrenceKey = nil
    }

    // MARK: - Background delivery (local notifications)

    private static let notificationPrefix = "activity-reminder-"

    /// Re-syncs one daily-repeating local notification per configured time, so
    /// reminders still arrive when the app isn't running — call again whenever
    /// the schedule or the activity list changes, same as
    /// RestraintNotificationScheduler's rescheduleAll. `activities` is only
    /// used to gate "don't bother scheduling if the list is empty."
    static func rescheduleAll(times: [ActivityReminderTime], activities: [VirtueActivity], isEnabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let toRemove = requests.map { $0.identifier }.filter { $0.hasPrefix(notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: toRemove)

            guard isEnabled, !activities.isEmpty else { return }

            for (index, time) in times.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Activity reminder"
                content.body = Self.message
                content.sound = .default

                var comps = DateComponents()
                comps.hour = time.hour
                comps.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

                let request = UNNotificationRequest(identifier: "\(notificationPrefix)\(index)", content: content, trigger: trigger)
                center.add(request)
            }
        }
    }
}
