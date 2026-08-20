import Foundation

/// Tracks how long the app is backgrounded within a configurable daily
/// window (e.g. 6 AM–10 PM) — "away time". Per-day totals are kept to the
/// second, split correctly across day/window boundaries the same way
/// DistractionTracker splits absence time across task boundaries.
class AwayTimeTracker: ObservableObject {
    static let shared = AwayTimeTracker()

    private let secondsKey  = "AwayTimeTracker.secondsByDay"
    private let pendingKey  = "AwayTimeTracker.pendingExitTime"
    private let fromKey     = "AwayTimeTracker.windowFromMinute"
    private let toKey       = "AwayTimeTracker.windowToMinute"
    private let enabledKey  = "AwayTimeTracker.isEnabled"

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    /// Minutes since midnight. Defaults to 6:00 AM.
    var windowFromMinute: Int {
        get { UserDefaults.standard.object(forKey: fromKey) as? Int ?? 360 }
        set {
            UserDefaults.standard.set(newValue, forKey: fromKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    /// Minutes since midnight. Defaults to 10:00 PM.
    var windowToMinute: Int {
        get { UserDefaults.standard.object(forKey: toKey) as? Int ?? 1320 }
        set {
            UserDefaults.standard.set(newValue, forKey: toKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    // MARK: - Storage

    private var secondsByDay: [String: Double] {
        get { UserDefaults.standard.object(forKey: secondsKey) as? [String: Double] ?? [:] }
        set {
            UserDefaults.standard.set(newValue, forKey: secondsKey)
            DispatchQueue.main.async { self.objectWillChange.send() }
        }
    }

    private var pendingExitTime: Date? {
        get { UserDefaults.standard.object(forKey: pendingKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
    }

    // MARK: - Lifecycle hooks (called from MigrationWrapper)

    /// Call when the app is backgrounded.
    func recordExit() {
        guard isEnabled else { return }
        pendingExitTime = Date()
    }

    /// Call when the app returns to foreground (or on launch, to settle a
    /// pending exit left over from a force-quit while backgrounded).
    func recordReturn() {
        guard let start = pendingExitTime else { return }
        pendingExitTime = nil
        let end = Date()
        guard end > start else { return }
        accumulate(from: start, to: end)
    }

    // MARK: - Query

    func seconds(on date: Date) -> Double {
        secondsByDay[dateFormatter.string(from: Calendar.current.startOfDay(for: date))] ?? 0
    }

    var todaySeconds: Double { seconds(on: Date()) }

    static func formatted(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return "\(h)h \(m)m \(s)s" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    // MARK: - Splitting

    /// Splits [start, end) day-by-day, clipping each day's slice to that
    /// day's configured window, and adds only the in-window seconds to each
    /// affected day's total.
    private func accumulate(from start: Date, to end: Date) {
        guard isEnabled else { return }
        let cal = Calendar.current
        var cursorDay = cal.startOfDay(for: start)
        let lastDay = cal.startOfDay(for: end)
        let from = windowFromMinute
        let to = windowToMinute
        guard to > from else { return } // misconfigured window — nothing to count

        var additions: [String: Double] = [:]

        while cursorDay <= lastDay {
            if let windowStart = cal.date(byAdding: .minute, value: from, to: cursorDay),
               let windowEnd = cal.date(byAdding: .minute, value: to, to: cursorDay) {
                let overlapStart = max(start, windowStart)
                let overlapEnd = min(end, windowEnd)
                if overlapEnd > overlapStart {
                    let key = dateFormatter.string(from: cursorDay)
                    additions[key, default: 0] += overlapEnd.timeIntervalSince(overlapStart)
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursorDay) else { break }
            cursorDay = next
        }

        guard !additions.isEmpty else { return }
        var stored = secondsByDay
        for (key, add) in additions {
            stored[key, default: 0] += add
        }
        secondsByDay = stored
    }
}
