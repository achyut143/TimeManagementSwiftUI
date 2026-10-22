import Foundation
import UserNotifications

/// Sit → stand → stretch cycle (stretch is optional), repeating from the
/// moment it was switched on. Default 30 / 30 / 5 minutes, all adjustable.
///
/// The phase is worked out from `startedAt` and the clock rather than a
/// running timer, so it stays correct across backgrounding and relaunches.
/// Phase changes are also queued as local notifications so they arrive
/// while the app isn't open.
enum StandReminder {
    static let enabledKey = "standReminder.enabled"
    static let sitMinutesKey = "standReminder.sitMinutes"
    static let standMinutesKey = "standReminder.standMinutes"
    static let stretchEnabledKey = "standReminder.stretchEnabled"
    static let stretchMinutesKey = "standReminder.stretchMinutes"
    static let startedAtKey = "standReminder.startedAt"

    static let defaultSitMinutes = 30
    static let defaultStandMinutes = 30
    static let defaultStretchEnabled = true
    static let defaultStretchMinutes = 5

    private static let notificationPrefix = "stand-reminder-"
    /// How many upcoming phase changes to keep scheduled. Topped up each time
    /// the app becomes active; iOS caps pending notifications at 64 app-wide.
    private static let notificationsAhead = 24

    enum Phase: String {
        case sit, stand, stretch
    }

    struct Status {
        let phase: Phase
        let secondsRemaining: Int
        /// When this phase began.
        let phaseStart: Date
    }

    private static var defaults: UserDefaults { .standard }

    // MARK: - Settings

    static var isEnabled: Bool { defaults.bool(forKey: enabledKey) }

    private static func minutes(_ key: String, _ fallback: Int) -> Int {
        let v = defaults.integer(forKey: key)
        return v > 0 ? v : fallback
    }

    static var sitMinutes: Int { minutes(sitMinutesKey, defaultSitMinutes) }
    static var standMinutes: Int { minutes(standMinutesKey, defaultStandMinutes) }
    static var stretchMinutes: Int { minutes(stretchMinutesKey, defaultStretchMinutes) }

    static var stretchEnabled: Bool {
        defaults.object(forKey: stretchEnabledKey) == nil
            ? defaultStretchEnabled
            : defaults.bool(forKey: stretchEnabledKey)
    }

    static var startedAt: Date {
        let t = defaults.double(forKey: startedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : Date()
    }

    /// The phases in one cycle, with their length in seconds.
    static var phases: [(phase: Phase, seconds: Int)] {
        var list: [(Phase, Int)] = [(.sit, sitMinutes * 60), (.stand, standMinutes * 60)]
        if stretchEnabled { list.append((.stretch, stretchMinutes * 60)) }
        return list
    }

    static func minutes(for phase: Phase) -> Int {
        switch phase {
        case .sit: return sitMinutes
        case .stand: return standMinutes
        case .stretch: return stretchMinutes
        }
    }

    /// Seconds from the start of a cycle to the start of `phase`.
    private static func offset(of phase: Phase) -> Int? {
        var total = 0
        for p in phases {
            if p.phase == phase { return total }
            total += p.seconds
        }
        return nil
    }

    static func status(at now: Date = Date()) -> Status {
        let list = phases
        let cycle = list.reduce(0) { $0 + $1.seconds }
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        var pos = elapsed % cycle
        for p in list {
            if pos < p.seconds {
                let remaining = p.seconds - pos
                return Status(phase: p.phase,
                              secondsRemaining: remaining,
                              phaseStart: now.addingTimeInterval(Double(remaining - p.seconds)))
            }
            pos -= p.seconds
        }
        // Not reachable: pos is always inside the cycle.
        return Status(phase: .sit, secondsRemaining: list[0].seconds, phaseStart: now)
    }

    static func next(after phase: Phase) -> Phase {
        let list = phases.map(\.phase)
        guard let i = list.firstIndex(of: phase) else { return .sit }
        return list[(i + 1) % list.count]
    }

    // MARK: - Acknowledgment

    /// Stable id for the current phase occurrence, for AcknowledgmentStore —
    /// same mechanism the calendar-task timer uses, so an acknowledged phase
    /// stays acknowledged across view reloads and app relaunches.
    private static func key(for status: Status) -> String {
        "stand-\(status.phase.rawValue)@\(Int(status.phaseStart.timeIntervalSince1970 / 60))"
    }

    static func isCurrentPhaseAcknowledged(at now: Date = Date()) -> Bool {
        let st = status(at: now)
        return AcknowledgmentStore.isAcknowledged(date: st.phaseStart, identifier: key(for: st))
    }

    static func acknowledgeCurrentPhase(at now: Date = Date()) {
        let st = status(at: now)
        AcknowledgmentStore.acknowledge(date: st.phaseStart, identifier: key(for: st))
    }

    // MARK: - Actions

    /// Turns the reminder on or off. Turning on starts a fresh sitting phase.
    static func setEnabled(_ on: Bool) {
        defaults.set(on, forKey: enabledKey)
        if on { startPhase(.sit) }
        reschedule()
    }

    /// Ends the current phase now and moves to the next one.
    static func skipToNextPhase() {
        startPhase(next(after: status().phase))
        reschedule()
    }

    /// Restarts the cycle with a fresh sitting phase.
    static func restart() {
        startPhase(.sit)
        reschedule()
    }

    /// Changes timing settings without jumping to a different phase: the
    /// current phase keeps its start time; only its length (and the rest of
    /// the cycle) changes.
    static func updateSettings(_ change: () -> Void) {
        let now = Date()
        let before = status(at: now)
        change()
        guard isEnabled else { return }
        if let off = offset(of: before.phase) {
            defaults.set(before.phaseStart.timeIntervalSince1970 - Double(off), forKey: startedAtKey)
        } else {
            // The current phase was removed (stretch turned off) — sit now.
            startPhase(.sit)
        }
        reschedule()
    }

    /// Starts a phase now. The user chose it, so it doesn't need acknowledging.
    private static func startPhase(_ phase: Phase) {
        let now = Date()
        let start = now.addingTimeInterval(-Double(offset(of: phase) ?? 0))
        defaults.set(start.timeIntervalSince1970, forKey: startedAtKey)
        acknowledgeCurrentPhase(at: now)
    }

    // MARK: - Notifications

    static func title(for phase: Phase) -> String {
        switch phase {
        case .sit: return "You can sit down"
        case .stand: return "Time to stand"
        case .stretch: return "Time to stretch"
        }
    }

    /// Replaces all pending stand notifications with the next ones from now.
    static func reschedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)

            guard isEnabled else { return }

            let current = status()
            var phase = current.phase
            var fireIn = TimeInterval(current.secondsRemaining)

            for i in 0..<notificationsAhead {
                phase = next(after: phase)
                let mins = minutes(for: phase)

                let content = UNMutableNotificationContent()
                content.title = title(for: phase)
                switch phase {
                case .sit: content.body = "Sit for \(mins) min."
                case .stand: content.body = "Stand for \(mins) min."
                case .stretch: content.body = "Stretch for \(mins) min."
                }
                content.body += " Open the app to acknowledge."
                content.sound = .default
                content.interruptionLevel = .timeSensitive

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireIn), repeats: false)
                center.add(UNNotificationRequest(identifier: "\(notificationPrefix)\(i)", content: content, trigger: trigger))

                fireIn += TimeInterval(mins * 60)
            }
        }
    }
}
